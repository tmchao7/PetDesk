import AppKit

/// 拖拽缓存托盘面板：接收拖入的文件/文件夹（NSDraggingDestination），
/// 并支持从托盘拖出（NSDraggingSource）。
///
/// 交互约定：
/// - 顶部把手区（高 26pt）拖拽 = 移动窗口
/// - 其余区域（文件行）拖拽 = 拖出文件（SwiftUI .onDrag），不移动窗口
@MainActor
final class DragShelfPanel: NSPanel, NSDraggingDestination, NSDraggingSource {
  /// 拖入新文件时回调（AppKit 主线程）。
  var onFilesDropped: (([URL]) -> Void)?

  /// 顶部拖拽把手高度（pt）。
  static let dragHandleHeight: CGFloat = 26

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    // 关闭背景拖动：只有顶部把手能移动窗口，文件行拖拽留给 .onDrag 拖出文件。
    isMovableByWindowBackground = false
    registerForDraggedTypes([.fileURL])
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// 关闭托盘（保留面板对象，可再次打开）。
  func dismissShelf() {
    orderOut(nil)
  }

  /// 安装顶部拖拽把手（在设置 contentView 后调用）。
  /// - Parameter contentHeight: 内容区高度（初始 contentRect 高度）。
  ///   不要用 contentView.bounds.height——安装时 hosting view 可能尚未布局
  ///   （bounds 为 0），会把把手定位到窗口外。
  func installDragHandle(contentHeight: CGFloat) {
    guard let contentView else { return }
    let handle = ShelfDragHandleView(
      frame: NSRect(
        x: 0,
        y: contentHeight - Self.dragHandleHeight,
        width: contentView.bounds.width,
        height: Self.dragHandleHeight
      )
    )
    handle.panel = self
    contentView.addSubview(handle)
    // 布局完成后把手宽度跟随内容区（高度固定顶部）。
    handle.autoresizingMask = [.width]
  }

  // MARK: - NSDraggingDestination

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) {}

  func draggingEnded(_ sender: NSDraggingInfo) {}

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls =
      sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [
          .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
    guard !urls.isEmpty else { return false }
    onFilesDropped?(urls)
    return true
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }
}

/// 顶部拖拽把手：仅该区域能移动托盘窗口。
/// 右侧 44pt 让给 SwiftUI 的关闭按钮（hitTest 返回 nil 穿透）。
@MainActor
private final class ShelfDragHandleView: NSView {
  weak var panel: DragShelfPanel?
  private var isDragging = false
  private var lastDragLocation = NSPoint.zero

  /// 右侧保留宽度（关闭按钮区域）。
  private static let rightReserve: CGFloat = 44

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard point.x <= bounds.width - Self.rightReserve else { return nil }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    isDragging = true
    lastDragLocation = NSEvent.mouseLocation  // 全局屏幕坐标
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDragging, let panel else { return }
    // 用全局坐标算位移（window 坐标在移动过程中会变化，会反馈回 delta 造成抖动）。
    let current = NSEvent.mouseLocation
    let dx = current.x - lastDragLocation.x
    let dy = current.y - lastDragLocation.y
    panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + dx, y: panel.frame.origin.y + dy))
    lastDragLocation = current
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }
}
