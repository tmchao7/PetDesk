import AppKit
import SwiftUI

@MainActor
final class PetHitTestHostingView<Content: View>: NSHostingView<Content> {
  /// Pet avatar size in points (set by PetWindowController).
  var petSize: CGFloat = 148

  /// Whether the bubble overlay is currently shown.
  var bubbleVisible = false

  /// Hooks used by the window controller to suspend high-frequency position
  /// persistence while the user is dragging the pet.
  var onUserDragBegan: (() -> Void)?
  var onUserDragEnded: (() -> Void)?

  /// Required for buttons and gestures to work inside a non-activating
  /// NSPanel.  Without this the panel never becomes key and SwiftUI
  /// interactions silently fail.
  override var needsPanelToBecomeKey: Bool { true }

  /// Deliver mouse events on the first click even when the window is not
  /// yet key.  Without this the first click only activates the panel and
  /// is swallowed (single-click interactions never fire).
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// 鼠标按下时的窗口内位置与窗口原点：拖动宠物时手动移动窗口。
  /// SwiftUI 手势会吞掉 mouseDown，isMovableByWindowBackground 无法从宠物
  /// 本体上触发拖动，因此在 NSView 层拦截 mouseDragged 完成移动。
  /// 拖动起点使用全局屏幕坐标（NSEvent.mouseLocation）而不是事件内的
  /// locationInWindow：窗口移动后，事件队列里的 locationInWindow 仍是相对
  /// 旧 frame 计算的位置，用它算位移会让窗口来回抖动/出现残影。
  private var dragStartScreenLocation: NSPoint?
  private var dragWindowOrigin: NSPoint?
  private var isUserDragging = false

  override func mouseDown(with event: NSEvent) {
    isUserDragging = true
    onUserDragBegan?()
    dragStartScreenLocation = NSEvent.mouseLocation
    dragWindowOrigin = window?.frame.origin
    super.mouseDown(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    super.mouseDragged(with: event)
    guard
      let start = dragStartScreenLocation,
      let origin = dragWindowOrigin,
      let window
    else { return }
    let current = NSEvent.mouseLocation
    window.setFrameOrigin(
      NSPoint(
        x: origin.x + (current.x - start.x),
        y: origin.y + (current.y - start.y)
      )
    )
  }

  override func mouseUp(with event: NSEvent) {
    dragStartScreenLocation = nil
    dragWindowOrigin = nil
    if isUserDragging {
      isUserDragging = false
      onUserDragEnded?()
    }
    super.mouseUp(with: event)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wantsLayer = true
    layer?.masksToBounds = false
  }

  private var petRegion: NSRect {
    NSRect(x: bounds.maxX - petSize - 40, y: bounds.minY, width: petSize + 40, height: petSize + 40)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // When the bubble is visible let SwiftUI handle all hit-testing so
    // bubble buttons receive taps.  When hidden, constrain clicks to the
    // pet region so the rest of the window is transparent to mouse events.
    if bubbleVisible { return super.hitTest(point) }

    guard petRegion.contains(point) else { return nil }
    return super.hitTest(point)
  }
}
