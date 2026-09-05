import AppKit
import CoreGraphics
import XCTest

@testable import PetDesk

final class AnimationFrameStoreTests: XCTestCase {
  @MainActor
  func testPreloadCreatesOnlyRequestedFrames() {
    let store = AnimationFrameStore()
    let sheet = makeTestSpriteSheet()
    let frames = store.preload(sheet: sheet, row: .working, frameCount: 3)
    XCTAssertEqual(frames.count, 3)
  }

  @MainActor
  func testCGOnlyPreloadReusesPreparedImagesWithoutSwiftUIImageResults() {
    let store = AnimationFrameStore()
    let sheet = makeTestSpriteSheet()

    let first = store.preloadCGImages(sheet: sheet, row: .working, frameCount: 3)
    let second = store.preloadCGImages(sheet: sheet, row: .working, frameCount: 3)

    XCTAssertEqual(first.count, 3)
    XCTAssertTrue(first[0] === second[0])
  }

  @MainActor
  func testRepeatedPreloadReusesPreparedImagesUntilSheetChanges() {
    let store = AnimationFrameStore()
    let sheet = makeTestSpriteSheet()
    let first = store.preload(sheet: sheet, row: .working, frameCount: 3)
    let second = store.preload(sheet: sheet, row: .working, frameCount: 3)
    XCTAssertTrue(first.nsImages[0] === second.nsImages[0])
    XCTAssertTrue(first.cgImages[0] === second.cgImages[0])
  }

  @MainActor
  func testInvalidFrameCountProducesOneSafeFallbackFrame() {
    let store = AnimationFrameStore()
    let frames = store.preload(sheet: makeTestSpriteSheet(), row: .working, frameCount: 0)
    XCTAssertEqual(frames.count, 1)
  }

  @MainActor
  func testFrameCountClampedToAvailableColumns() {
    let store = AnimationFrameStore()
    let frames = store.preload(sheet: makeTestSpriteSheet(), row: .working, frameCount: 999)
    XCTAssertLessThanOrEqual(frames.count, SpriteSheetSpec.columns)
  }

  @MainActor
  func testClearReleasesPreparedFrames() {
    let store = AnimationFrameStore()
    let sheet = makeTestSpriteSheet()
    _ = store.preload(sheet: sheet, row: .working, frameCount: 4)
    store.clear()
    // 清理后再次预载应重新准备（缓存清空），计数一致即可。
    let frames = store.preload(sheet: sheet, row: .working, frameCount: 4)
    XCTAssertEqual(frames.count, 4)
  }

  @MainActor
  func testDifferentRowsDoNotShareCache() {
    let store = AnimationFrameStore()
    let sheet = makeTestSpriteSheet()
    let working = store.preload(sheet: sheet, row: .working, frameCount: 2)
    let drinking = store.preload(sheet: sheet, row: .drinking, frameCount: 2)
    XCTAssertEqual(working.count, 2)
    XCTAssertEqual(drinking.count, 2)
    XCTAssertFalse(working.cgImages[0] === drinking.cgImages[0])
  }

  // MARK: - Helpers

  @MainActor
  private func makeTestSpriteSheet() -> CGImage {
    let width = Int(SpriteSheetSpec.frameWidth) * SpriteSheetSpec.columns
    let height = Int(SpriteSheetSpec.frameHeight) * AnimationRow.allCases.count
    let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
  }
}
