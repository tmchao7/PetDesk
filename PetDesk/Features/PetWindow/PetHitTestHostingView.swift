import AppKit
import SwiftUI

@MainActor
final class PetHitTestHostingView<Content: View>: NSHostingView<Content> {
  /// Pet avatar size in points (set by PetWindowController from the
  /// environment's petScale).
  var petSize: CGFloat = 148

  /// Whether the bubble overlay is currently shown.
  var bubbleVisible = false

  /// Required for buttons and gestures to work inside a non-activating
  /// NSPanel.  Without this the panel never becomes key and SwiftUI
  /// interactions silently fail.
  override var needsPanelToBecomeKey: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wantsLayer = true
    layer?.masksToBounds = false
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Pet sits at the bottom-trailing corner; bubble floats above it.
    // Compute a combined interactive region instead of depending on a
    // separately-synced bubbleVisible flag, which can race with the
    // SwiftUI transition animation.
    let petRegion = NSRect(
      x: bounds.maxX - petSize - 24,
      y: bounds.minY + 8,
      width: petSize + 24,
      height: petSize + 24
    )
    let bubbleRegion = NSRect(
      x: bounds.maxX - 248,
      y: bounds.maxY - 190,
      width: 248,
      height: 182
    )
    if petRegion.contains(point) || (bubbleVisible && bubbleRegion.contains(point)) {
      return super.hitTest(point)
    }
    return nil
  }
}
