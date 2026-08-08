import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 托盘拖出方式：复制（默认）或移动。
/// 注意：目标 app 决定最终操作——微信/QQ/邮件等外部 app 只接受复制；
/// 移动仅对 Finder 等支持 move 的目标生效。
enum ShelfDragOutMode: String, Sendable {
  case copy
  case move
}

/// 托盘「拖出文件」的 pasteboard 构造与复制/移动操作掩码。
/// 与视图分离以便单元测试：拖拽 pasteboard 必须携带真实 file:// 路径，
/// Finder/微信/QQ 才能据此解析并消费文件。
enum ShelfDragOutPasteboard {
  /// 为真实文件构造拖拽 pasteboard 条目。
  /// - `public.file-url`：真实 `file://` URL 字符串（Finder/终端读取）。
  /// - 图片内容 UTI（如 `public.png`）：通过 dataProvider 按需懒加载，
  ///   微信/QQ/图片编辑器等直接消费内容的 app 需要它；不整读大文件。
  /// - 返回的 provider 必须由调用方强持有到拖拽结束（pasteboard 持弱引用）。
  static func makeItem(for url: URL) -> (
    item: NSPasteboardItem, provider: ShelfDragOutDataProvider?
  ) {
    let item = NSPasteboardItem()
    item.setString(url.absoluteString, forType: .fileURL)

    var provider: ShelfDragOutDataProvider?
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
      let dataProvider = ShelfDragOutDataProvider(url: url)
      item.setDataProvider(dataProvider, forTypes: [NSPasteboard.PasteboardType(type.identifier)])
      provider = dataProvider
    }
    return (item, provider)
  }

  /// 复制/移动模式的拖拽操作掩码。
  /// 注意：目标 app 决定最终操作——微信/QQ/邮件等外部 app 只接受复制；
  /// 移动仅对 Finder 等支持 move 的目标生效。
  static func operationMask(for mode: ShelfDragOutMode) -> NSDragOperation {
    switch mode {
    case .copy: .copy
    case .move: [.copy, .move]
    }
  }
}

/// 图片内容 UTI 的懒加载数据提供者：目标请求时才读取真实文件数据。
/// 需继承 NSObject（NSPasteboardItemDataProvider 继承 NSObjectProtocol）。
final class ShelfDragOutDataProvider: NSObject, NSPasteboardItemDataProvider {
  private let url: URL

  init(url: URL) {
    self.url = url
  }

  func pasteboard(
    _ pasteboard: NSPasteboard?,
    item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    guard let data = try? Data(contentsOf: url) else { return }
    item.setData(data, forType: type)
  }
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
  /// 拖出方式（copy / move）。
  var mode: ShelfDragOutMode = .copy
  /// 点击移除按钮时回调（AppKit 主线程）。
  var onRemove: (() -> Void)?

  private let iconView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let removeButton = NSButton()

  private var isDragging = false
  /// 拖拽内容 UTI 数据提供者需存活到拖拽结束（NSPasteboardItem 持弱引用）。
  private var activeDataProvider: ShelfDragOutDataProvider?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
    layer?.cornerRadius = 6

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
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

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

  @objc private func removeTapped() {
    onRemove?()
  }

  // MARK: - 拖出

  override func mouseDown(with event: NSEvent) {
    isDragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isDragging, let filePath else { return }
    isDragging = true

    let url = URL(fileURLWithPath: filePath)
    let (item, provider) = ShelfDragOutPasteboard.makeItem(for: url)
    activeDataProvider = provider
    let draggingItem = NSDraggingItem(pasteboardWriter: item)
    // 拖拽预览：真实文件图标，避免空白拖拽。
    let image = NSWorkspace.shared.icon(forFile: filePath)
    draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: image)
    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
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
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(filePath, forType: .string)
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    ShelfDragOutPasteboard.operationMask(for: mode)
  }
}

/// SwiftUI 到 AppKit 行视图的最小桥接。
struct ShelfRowRepresentable: NSViewRepresentable {
  let path: String
  let mode: ShelfDragOutMode
  let onRemove: () -> Void

  func makeNSView(context: Context) -> ShelfRowView {
    let view = ShelfRowView()
    view.filePath = path
    view.mode = mode
    view.onRemove = onRemove
    return view
  }

  func updateNSView(_ nsView: ShelfRowView, context: Context) {
    nsView.filePath = path
    nsView.mode = mode
    nsView.onRemove = onRemove
  }
}
