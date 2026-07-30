import AppKit
import SwiftUI

@MainActor
final class PetHitTestHostingView<Content: View>: NSHostingView<Content> {
  var bubbleVisible = false

  override func hitTest(_ point: NSPoint) -> NSView? {
    let petRegion = NSRect(x: bounds.maxX - 180, y: 0, width: 180, height: 180)
    let bubbleRegion = NSRect(x: 0, y: 140, width: 250, height: 120)
    guard petRegion.contains(point) || (bubbleVisible && bubbleRegion.contains(point)) else {
      return nil
    }
    return super.hitTest(point)
  }
}
