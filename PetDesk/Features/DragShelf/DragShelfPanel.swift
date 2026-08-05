import AppKit

/// 拖拽缓存托盘面板：接收拖入的文件/文件夹（NSDraggingDestination），
/// 并支持从托盘拖出（NSDraggingSource）。
@MainActor
final class DragShelfPanel: NSPanel, NSDraggingDestination, NSDraggingSource {
  /// 拖入新文件时回调（AppKit 主线程）。
  var onFilesDropped: (([URL]) -> Void)?
  /// 拖入悬停高亮状态。
  private(set) var isHighlighted = false

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel, .titled],
      backing: .buffered,
      defer: false
    )
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    registerForDraggedTypes([.fileURL])
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // MARK: - NSDraggingDestination

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    isHighlighted = true
    return .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    isHighlighted = false
  }

  func draggingEnded(_ sender: NSDraggingInfo) {
    isHighlighted = false
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    isHighlighted = false
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
