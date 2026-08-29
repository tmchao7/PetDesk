import CoreGraphics
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// 横向帧条带自动切帧：单次 AI 生成“N 帧横向长图”是角色一致性最好的
/// 生成方式，导入时应自动切分为 N 帧；不像条带的宽图必须原样回退。
final class PoseSheetSlicerTests: XCTestCase {
  /// 合成条带图：N 格等宽、绿背景，每格一个深蓝圆形主体（可留缝隙）。
  private func makeStrip(
    cellSize: Int,
    frameCount: Int,
    gutter: Int = 0,
    subjectsIn: (Int) -> Bool = { _ in true }
  ) -> CGImage? {
    let width = frameCount * cellSize + (frameCount - 1) * gutter
    let height = cellSize
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { return nil }
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
    for index in 0..<frameCount where subjectsIn(index) {
      let originX = index * (cellSize + gutter)
      let diameter = cellSize / 2
      // Quartz 坐标（原点左下）；圆放在格内偏下位置。
      context.fill(
        CGRect(
          x: originX + cellSize / 4, y: cellSize / 4,
          width: diameter, height: diameter
        )
      )
    }
    return context.makeImage()
  }

  func testSliceDetectsFourFrameStrip() throws {
    guard let strip = makeStrip(cellSize: 256, frameCount: 4) else {
      return XCTFail("strip fixture should render")
    }
    let frames = PoseSheetSlicer.sliceStrip(from: strip)
    XCTAssertEqual(frames.count, 4, "4-cell strip should slice into 4 frames")
    XCTAssertEqual(frames[0].width, 256)
    XCTAssertEqual(frames[0].height, 256)
  }

  func testSliceToleratesSmallGutters() throws {
    guard let strip = makeStrip(cellSize: 256, frameCount: 4, gutter: 10) else {
      return XCTFail("strip fixture should render")
    }
    let frames = PoseSheetSlicer.sliceStrip(from: strip)
    XCTAssertEqual(frames.count, 4, "strip with small gutters should still slice")
  }

  func testSliceFallsBackForWideSingleSubject() throws {
    // 2:1 宽图但单个主体横跨中线：切开会切断角色，必须回退单帧。
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: 512, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue
      )
    else { return XCTFail("fixture should render") }
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 128, y: 64, width: 256, height: 128))
    guard let spanning = context.makeImage() else { return XCTFail("fixture should render") }

    let frames = PoseSheetSlicer.sliceStrip(from: spanning)
    XCTAssertEqual(frames.count, 1, "subject crossing the cut line should not slice")
    XCTAssertTrue(frames[0] === spanning)
  }

  func testSliceFallsBackWhenACellIsEmpty() throws {
    guard let strip = makeStrip(cellSize: 256, frameCount: 4, subjectsIn: { $0 < 2 }) else {
      return XCTFail("strip fixture should render")
    }
    let frames = PoseSheetSlicer.sliceStrip(from: strip)
    XCTAssertEqual(frames.count, 1, "strip with an empty cell should fall back to one frame")
  }

  func testSliceFallsBackForNonIntegralRatios() throws {
    guard let odd = makeStrip(cellSize: 256, frameCount: 2, gutter: 128) else {
      return XCTFail("strip fixture should render")
    }
    // 640×256（2.5:1）：无法整除成等宽格，应回退单帧。
    XCTAssertEqual(PoseSheetSlicer.sliceStrip(from: odd).count, 1)

    // 512×288（1.78:1，普通照片构图）低于条带阈值，应回退单帧。
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: 512, height: 288, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue
      )
    else { return XCTFail("fixture should render") }
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 512, height: 288))
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 192, y: 72, width: 128, height: 128))
    guard let photo = context.makeImage() else { return XCTFail("fixture should render") }
    XCTAssertEqual(PoseSheetSlicer.sliceStrip(from: photo).count, 1)
  }
}
