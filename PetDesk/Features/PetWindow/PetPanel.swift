import AppKit

@MainActor
final class PetPanel: NSPanel, NSDraggingDestination {
  /// 拖入文件时回调（urls 非空）。
  var onFilesDropped: (([URL]) -> Void)?

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    hidesOnDeactivate = false
    // 窗口移动由 PetHitTestHostingView.mouseDragged 手动完成；
    // 关闭 AppKit 背景拖动，避免与宠物本体上的拖动路径冲突。
    isMovableByWindowBackground = false
    animationBehavior = .utilityWindow
    acceptsMouseMovedEvents = true
    becomesKeyOnlyIfNeeded = false
  }

  // MARK: - NSDraggingDestination（拖文件到桌宠 → 暂存托盘）

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    .copy
  }

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

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// 不约束窗口位置：默认约束会把窗口限制在可见屏幕区域内，
  /// 在较小屏幕上 500pt 高的窗口因此只能停在中下部，无法拖到上半部分。
  /// 社区标准解法（StackOverflow: constrainFrameRect override）是原样返回，
  /// 允许用户把桌宠拖到屏幕任意位置；若完全拖出屏幕，下次启动 restore 会拉回。
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}
