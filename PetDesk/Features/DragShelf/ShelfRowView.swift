import AppKit
import SwiftUI

/// 托盘「拖出文件」的 pasteboard 构造与拖拽操作掩码。
/// 与视图分离以便单元测试：拖拽 pasteboard 必须携带真实 file:// 路径，
/// Finder/微信/QQ 才能据此解析并消费文件。
enum ShelfDragOutPasteboard {
  /// 构造与 Finder 拖拽等价的 pasteboard 写入器：直接返回 `NSURL`。
  /// AppKit 会据此生成 `public.file-url` + `NSFilenamesPboardType` +
  /// Apple URL 类型——Finder 读 file-url，微信/QQ 等 IM 目标读
  /// `NSFilenamesPboardType`（路径数组）。两者缺一，对应目标就会拒绝拖拽。
  /// （`NSPasteboardItem` 无法携带 `NSFilenamesPboardType`：它不是合法 UTI，
  /// `setPropertyList` 会被静默丢弃。）
  static func makeWriter(for url: URL) -> NSURL {
    url as NSURL
  }

  /// 旧式 `NSFilenamesPboardType`（已废弃但仍被微信/QQ 等读取）。
  static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

  /// 源允许的拖拽操作：同时声明复制与移动，由系统/目标按 Finder 语义决定——
  /// 同盘=移动、跨盘=复制；微信/QQ/邮件等外部 app 只接受复制。
  static let allowedOperations: NSDragOperation = [.copy, .move]
}

/// 托盘单行条目的 AppKit 视图：图标 + 文件名 + 移除按钮 + 拖出 + 右键菜单。
///
/// 整行作为拖出源（NSDraggingSource）直接接收鼠标事件，因此拖拽必然能启动。
/// （旧方案把拖拽视图放在 SwiftUI 行的 `.background` 里——它被压在行内容
/// 后面，图标/文件名/按钮把 mouseDown 事件吞掉，`beginDraggingSession` 从未
/// 触发，导致文件拖不到桌面或微信/QQ。）
@MainActor
final class ShelfRowView: NSView, NSDraggingSource {
  /// 被拖出的文件路径。
  var filePath: String? {
    didSet { refreshContent() }
  }
  /// 共享选择状态（单选 / Shift 连选 / Command 切换）。
  var selection: ShelfSelection?
  /// 托盘当前全部路径（显示顺序），用于 Shift 连选与整组拖出顺序。
  var items: [String] = []
  /// 是否被选中（SwiftUI 观察 selection 后经 updateNSView 刷新）。
  var isSelected = false {
    didSet { updateHighlight() }
  }
  /// 点击移除按钮时回调（AppKit 主线程）。
  var onRemove: (() -> Void)?
  /// 拖拽以 .move 结束（同盘移动）后回调，用于从托盘移除已移走的原文件。
  var onMoveCompleted: (([String]) -> Void)?

  private let iconView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let removeButton = NSButton()

  private var isDragging = false
  /// 单击已选中行时，先保持整组（便于整组拖出），mouseUp 未拖拽再单选。
  private var pendingDeselect = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
    updateHighlight()

    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    nameLabel.font = .systemFont(ofSize: 12)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.textColor = .secondaryLabelColor
    addSubview(nameLabel)

    if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "移除") {
      removeButton.image = image
    }
    removeButton.isBordered = false
    removeButton.contentTintColor = .secondaryLabelColor
    removeButton.target = self
    removeButton.action = #selector(removeTapped)
    removeButton.toolTip = "移除"
    addSubview(removeButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    let h = bounds.height
    let insetX: CGFloat = 8
    let iconSize: CGFloat = 24
    let buttonSize: CGFloat = 20
    iconView.frame = NSRect(x: insetX, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
    let buttonX = bounds.width - insetX - buttonSize
    removeButton.frame = NSRect(
      x: buttonX, y: (h - buttonSize) / 2, width: buttonSize, height: buttonSize)
    nameLabel.frame = NSRect(
      x: insetX + iconSize + 8,
      y: 0,
      width: max(0, buttonX - (insetX + iconSize + 8) - 4),
      height: h
    )
  }

  private func refreshContent() {
    guard let filePath else {
      iconView.image = nil
      nameLabel.stringValue = ""
      return
    }
    iconView.image = NSWorkspace.shared.icon(forFile: filePath)
    nameLabel.stringValue = (filePath as NSString).lastPathComponent
  }

  private func updateHighlight() {
    let color =
      isSelected
      ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
      : NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
    layer?.backgroundColor = color
  }

  @objc private func removeTapped() {
    onRemove?()
  }

  // MARK: - 选择与拖出

  override func mouseDown(with event: NSEvent) {
    isDragging = false
    guard let filePath, let selection else { return }
    let shift = event.modifierFlags.contains(.shift)
    let command = event.modifierFlags.contains(.command)
    let plainClickOnSelected = !shift && !command && selection.isSelected(filePath)
    pendingDeselect = plainClickOnSelected
    if !plainClickOnSelected {
      selection.click(on: filePath, in: items, shift: shift, command: command)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isDragging, let filePath else { return }
    isDragging = true
    pendingDeselect = false

    // 拖的是已选中行 → 整组拖出；否则只拖这一行。
    let paths = selection?.dragPaths(for: filePath, in: items) ?? [filePath]
    let draggingItems: [NSDraggingItem] = paths.enumerated().map { index, path in
      let item = NSDraggingItem(
        pasteboardWriter: ShelfDragOutPasteboard.makeWriter(for: URL(fileURLWithPath: path)))
      // 拖拽预览：真实文件图标，多文件按序号错开像一叠。
      let image = NSWorkspace.shared.icon(forFile: path)
      let offset = CGFloat(index) * 14
      item.setDraggingFrame(NSRect(x: offset, y: 0, width: 48, height: 48), contents: image)
      return item
    }
    beginDraggingSession(with: draggingItems, event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    if pendingDeselect, let filePath, let selection {
      selection.click(on: filePath, in: items, shift: false, command: false)
    }
    pendingDeselect = false
  }

  // MARK: - 右键菜单

  override func menu(for event: NSEvent) -> NSMenu? {
    guard filePath != nil else { return nil }
    let menu = NSMenu()
    let copyItem = NSMenuItem(title: "复制路径", action: #selector(copyPath), keyEquivalent: "")
    copyItem.target = self
    menu.addItem(copyItem)
    return menu
  }

  @objc private func copyPath() {
    guard let filePath else { return }
    let paths = selection?.dragPaths(for: filePath, in: items) ?? [filePath]
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    ShelfDragOutPasteboard.allowedOperations
  }

  /// 同盘移动：目标已复制到新位置，源侧删除原文件完成"移动"，并通知从托盘移除。
  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    guard operation.contains(.move), let filePath else { return }
    let paths = selection?.dragPaths(for: filePath, in: items) ?? [filePath]
    for path in paths {
      try? FileManager.default.removeItem(atPath: path)
    }
    onMoveCompleted?(paths)
  }
}

/// SwiftUI 到 AppKit 行视图的最小桥接。
struct ShelfRowRepresentable: NSViewRepresentable {
  let path: String
  let onRemove: () -> Void
  let onMoveCompleted: ([String]) -> Void
  let selection: ShelfSelection
  let isSelected: Bool
  let items: [String]

  func makeNSView(context: Context) -> ShelfRowView {
    let view = ShelfRowView()
    view.filePath = path
    view.onRemove = onRemove
    view.onMoveCompleted = onMoveCompleted
    view.selection = selection
    view.items = items
    view.isSelected = isSelected
    return view
  }

  func updateNSView(_ nsView: ShelfRowView, context: Context) {
    nsView.filePath = path
    nsView.onRemove = onRemove
    nsView.onMoveCompleted = onMoveCompleted
    nsView.selection = selection
    nsView.items = items
    nsView.isSelected = isSelected
  }
}
