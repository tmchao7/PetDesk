import AppKit
import SwiftUI

@MainActor
final class PetHitTestHostingView<Content: View>: NSHostingView<Content> {
  var bubbleVisible = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wantsLayer = true
    layer?.masksToBounds = false
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // When the bubble is visible let SwiftUI handle all hit-testing so
    // bubble buttons receive taps.  When hidden, constrain clicks to the
    // pet region so the rest of the window is transparent to mouse events.
    if bubbleVisible { return super.hitTest(point) }

    let petRegion = NSRect(x: bounds.maxX - 180, y: 0, width: 180, height: 180)
    guard petRegion.contains(point) else { return nil }
    return super.hitTest(point)
  }
}
