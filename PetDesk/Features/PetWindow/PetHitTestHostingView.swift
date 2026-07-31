import AppKit
import SwiftUI

@MainActor
final class PetHitTestHostingView<Content: View>: NSHostingView<Content> {
  /// Pet avatar size in points (set by PetWindowController).
  var petSize: CGFloat = 148

  /// Whether the bubble overlay is currently shown.
  var bubbleVisible = false

  /// Called when the user clicks the pet avatar.  Handled at the AppKit
  /// layer because SwiftUI gestures inside a non-activating transparent
  /// NSPanel are unreliable for synthesized (XCUITest) click events.
  var onPetClick: (() -> Void)?

  /// Required for buttons and gestures to work inside a non-activating
  /// NSPanel.  Without this the panel never becomes key and SwiftUI
  /// interactions silently fail.
  override var needsPanelToBecomeKey: Bool { true }

  /// Deliver mouse events on the first click even when the window is not
  /// yet key.  Without this the first click only activates the panel and
  /// is swallowed (single-click interactions never fire).
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wantsLayer = true
    layer?.masksToBounds = false
  }

  private var petRegion: NSRect {
    NSRect(x: bounds.maxX - petSize - 40, y: bounds.minY, width: petSize + 40, height: petSize + 40)
  }

  private var bubbleRegion: NSRect {
    NSRect(x: bounds.maxX - 248, y: bounds.maxY - 190, width: 248, height: 182)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // When the bubble is visible let SwiftUI handle all hit-testing so
    // bubble buttons receive taps.  When hidden, constrain clicks to the
    // pet region so the rest of the window is transparent to mouse events.
    if bubbleVisible { return super.hitTest(point) }

    guard petRegion.contains(point) else { return nil }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    // Use window coordinates (bottom-left origin) to match petRegion, which
    // hitTest receives in the same coordinate space.  Converting to the
    // hosting view's flipped coordinates would invert the y axis and miss
    // the region check.
    let point = event.locationInWindow
    // Clicks on the pet toggle the quick actions; clicks elsewhere in the
    // window fall through (handled by hitTest returning nil).
    if !bubbleVisible, petRegion.contains(point) {
      onPetClick?()
      return
    }
    super.mouseDown(with: event)
  }
}
