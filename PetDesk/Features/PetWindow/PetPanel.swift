import AppKit

@MainActor
final class PetPanel: NSPanel {
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
    isMovableByWindowBackground = true
    animationBehavior = .utilityWindow
    acceptsMouseMovedEvents = true
    becomesKeyOnlyIfNeeded = false
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
