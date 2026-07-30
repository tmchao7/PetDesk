import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class ScreenPositionStoreTests: XCTestCase {
  private let suiteName = "ScreenPositionStoreTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults?.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  @MainActor
  func testSaveAndRestoreRoundTrips() {
    let store = ScreenPositionStore(defaults: defaults)
    let visible = [CGRect(x: 0, y: 0, width: 1_920, height: 1_080)]

    store.save(frame: NSRect(x: 100, y: 200, width: 180, height: 180))
    let restored = store.restore(
      size: NSSize(width: 180, height: 180), visibleFrames: visible)

    XCTAssertEqual(restored.origin.x, 100)
    XCTAssertEqual(restored.origin.y, 200)
  }

  @MainActor
  func testResetClearsStoredPosition() {
    let store = ScreenPositionStore(defaults: defaults)
    let visible = [CGRect(x: 0, y: 0, width: 1_920, height: 1_080)]

    store.save(frame: NSRect(x: 100, y: 200, width: 180, height: 180))
    store.reset()
    let restored = store.restore(
      size: NSSize(width: 180, height: 180), visibleFrames: visible)

    XCTAssertNotEqual(restored.origin.x, 100)
    XCTAssertNotEqual(restored.origin.y, 200)
  }

  @MainActor
  func testRestoreClampsOffscreenPosition() {
    let store = ScreenPositionStore(defaults: defaults)
    let visible = [CGRect(x: 0, y: 0, width: 1_000, height: 800)]

    store.save(frame: NSRect(x: 2_000, y: -500, width: 180, height: 180))
    let restored = store.restore(
      size: NSSize(width: 180, height: 180), visibleFrames: visible)

    XCTAssertTrue(
      visible[0].contains(restored), "restored frame should be clamped inside visible area")
  }

  @MainActor
  func testRestoreDefaultsWhenNothingStored() {
    let store = ScreenPositionStore(defaults: defaults)
    let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

    let restored = store.restore(
      size: NSSize(width: 180, height: 180), visibleFrames: [screen])

    // defaultFrame places at bottom-right: maxX - width - 24, minY + 24
    XCTAssertEqual(restored.origin.x, 1_920 - 180 - 24)
    XCTAssertEqual(restored.origin.y, 24)
  }
}
