import SwiftUI
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class PetHitTestHostingViewTests: XCTestCase {
  @MainActor
  func testHitTestReturnsNilOutsideBothRegions() {
    let view = makeView(width: 320, height: 260)
    // Outside pet region (bottom-right 180x180) and bubble region (top-left 250x120)
    XCTAssertNil(view.hitTest(NSPoint(x: 200, y: 130)))
  }

  @MainActor
  func testHitTestReturnsViewInsidePetRegion() {
    let view = makeView(width: 320, height: 260)
    // petRegion: (maxX - 180, 0, 180, 180) = (140, 0, 180, 180)
    let result = view.hitTest(NSPoint(x: 200, y: 90))
    XCTAssertNotNil(result)
  }

  @MainActor
  func testBubbleRegionIgnoredWhenHidden() {
    let view = makeView(width: 320, height: 260)
    view.bubbleVisible = false
    // bubbleRegion: (0, 140, 250, 120)
    XCTAssertNil(view.hitTest(NSPoint(x: 100, y: 200)))
  }

  @MainActor
  func testBubbleRegionRespondsWhenVisible() {
    let view = makeView(width: 320, height: 260)
    view.bubbleVisible = true
    // bubbleRegion: (0, 140, 250, 120)
    let result = view.hitTest(NSPoint(x: 100, y: 200))
    XCTAssertNotNil(result)
  }

  @MainActor
  private func makeView(width: CGFloat, height: CGFloat) -> PetHitTestHostingView<EmptyView> {
    let view = PetHitTestHostingView(rootView: EmptyView())
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(
      contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    return view
  }
}
