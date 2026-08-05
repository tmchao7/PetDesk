import AppKit

/// 托盘拖出方式：复制（默认）或移动。
/// 注意：目标 app 决定最终操作——微信/QQ/邮件等外部 app 只接受复制；
/// 移动仅对 Finder 等支持 move 的目标生效。
enum ShelfDragOutMode: String, Sendable {
  case copy
  case move
}

/// 托盘单行文件的 AppKit 拖出源：
/// 用 NSDraggingSession 启动拖拽，sourceOperationMask 按用户选择的
/// 复制/移动模式返回（SwiftUI 的 .onDrag 无法控制 mask，只能复制）。
@MainActor
final class ShelfDragOutView: NSView, NSDraggingSource {
  /// 被拖出的文件路径。
  var filePath: String?
  /// 拖出方式（copy / move）。
  var mode: ShelfDragOutMode = .copy

  private var isDragging = false

  override func mouseDown(with event: NSEvent) {
    isDragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isDragging, let filePath else { return }
    isDragging = true

    let item = NSPasteboardItem()
    item.setString(filePath, forType: .fileURL)
    let pasteboard = NSPasteboard()
    pasteboard.clearContents()
    pasteboard.writeObjects([item])

    let draggingItem = NSDraggingItem(pasteboardWriter: item)
    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    switch mode {
    case .copy: .copy
    case .move: [.copy, .move]
    }
  }
}
