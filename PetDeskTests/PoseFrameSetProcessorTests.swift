import CoreGraphics
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// 跨帧归一化：一组姿势帧（同一状态的多张动作帧）处理后应共享同一缩放、
/// 对齐到同一锚点（水平质心 + 垂直底边基线），并量化报告生成端漂移。
final class PoseFrameSetProcessorTests: XCTestCase {
  /// 合成一帧姿势图：纯色背景 + 矩形主体（视觉坐标，y 从顶部起算）。
  private func makeFrame(
    width: Int,
    height: Int,
    background: (r: CGFloat, g: CGFloat, b: CGFloat),
    subjectRect: CGRect,
    subjectColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.1, 0.2, 0.7)
  ) -> CGImage? {
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
    context.setFillColor(
      CGColor(red: background.r, green: background.g, blue: background.b, alpha: 1)
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // 视觉坐标 → Quartz 坐标（原点在左下）。
    let quartzRect = CGRect(
      x: subjectRect.origin.x,
      y: CGFloat(height) - subjectRect.maxY,
      width: subjectRect.width,
      height: subjectRect.height
    )
    context.setFillColor(
      CGColor(red: subjectColor.r, green: subjectColor.g, blue: subjectColor.b, alpha: 1)
    )
    context.fill(quartzRect)
    return context.makeImage()
  }

  /// 输出单元的主体包围盒（alpha > 8，视觉坐标 y 从顶部起算）。
  private func subjectBBox(in cell: CGImage) -> CGRect? {
    let width = cell.width
    let height = cell.height
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
      ),
      let data = context.data
    else { return nil }
    context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)
    var minColumn = width
    var maxColumn = -1
    var minRow = height
    var maxRow = -1
    for row in 0..<height {
      for column in 0..<width {
        let alpha = bytes[row * context.bytesPerRow + column * 4 + 3]
        if alpha > 8 {
          minColumn = min(minColumn, column)
          maxColumn = max(maxColumn, column)
          minRow = min(minRow, row)
          maxRow = max(maxRow, row)
        }
      }
    }
    guard maxColumn >= minColumn, maxRow >= minRow else { return nil }
    return CGRect(
      x: minColumn,
      y: minRow,
      width: maxColumn - minColumn + 1,
      height: maxRow - minRow + 1
    )
  }

  /// 平移漂移（±6 源像素 ≈ ±8.9 单元像素，在矫正范围内）应被完全对齐：
  /// 三帧输出单元的主体包围盒逐像素一致。
  func testProcessAlignsTranslatedFramesWithinClamp() throws {
    let canvas = 256
    let frames = try [-6, 0, 6].map { offset -> CGImage in
      guard
        let frame = makeFrame(
          width: canvas,
          height: canvas,
          background: (0, 1, 0),
          subjectRect: CGRect(
            x: 88 + CGFloat(offset), y: 48, width: 80, height: 140)
        )
      else { throw NSError(domain: "test", code: 1) }
      return frame
    }

    let result = try PoseFrameSetProcessor.process(images: frames)

    XCTAssertEqual(result.cells.count, 3)
    let boxes = try result.cells.map { cell -> CGRect in
      guard let box = subjectBBox(in: cell) else {
        throw NSError(domain: "test", code: 2)
      }
      return box
    }
    for box in boxes {
      XCTAssertEqual(box.width, boxes[0].width, accuracy: 2)
      XCTAssertEqual(box.height, boxes[0].height, accuracy: 2)
      XCTAssertEqual(box.minX, boxes[0].minX, accuracy: 2)
      XCTAssertEqual(box.minY, boxes[0].minY, accuracy: 2)
    }
    XCTAssertFalse(
      result.diagnostics.exceedsDriftThreshold,
      "小幅平移属于可矫正漂移，不应触发告警")
  }

  /// 缩放漂移：所有帧共享同一缩放（最大包围盒决定），任何帧不被放大或裁切；
  /// 相对大小差异保留为动画内容，面积比未超阈值时不告警。
  func testProcessUsesCommonScaleForSizeDrift() throws {
    let canvas = 256
    guard
      let small = makeFrame(
        width: canvas, height: canvas, background: (0, 1, 0),
        subjectRect: CGRect(x: 88, y: 48, width: 80, height: 140)),
      let large = makeFrame(
        width: canvas, height: canvas, background: (0, 1, 0),
        subjectRect: CGRect(x: 84, y: 41, width: 88, height: 154))
    else { throw NSError(domain: "test", code: 1) }

    let result = try PoseFrameSetProcessor.process(images: [small, large])

    XCTAssertEqual(result.cells.count, 2)
    guard let boxA = subjectBBox(in: result.cells[0]),
      let boxB = subjectBBox(in: result.cells[1])
    else {
      return XCTFail("cells should contain a subject")
    }
    // 统一缩放：单元尺寸 / 源尺寸 两帧一致（1.35 = 208/154）。
    XCTAssertEqual(boxB.width / 88, boxA.width / 80, accuracy: 0.03)
    // 最大的帧也不被裁切。
    XCTAssertLessThanOrEqual(boxB.width, 192.5)
    XCTAssertLessThanOrEqual(boxB.height, 208.5)
    // 面积比 (88/80)² ≈ 1.21 < 1.26，不触发告警。
    XCTAssertFalse(result.diagnostics.exceedsDriftThreshold)
  }

  /// 超阈值漂移：离群帧平移 30 源像素（≈44.6 单元像素 > 18px 阈值）应触发
  /// 告警；矫正被夹紧在 18 单元像素内（部分修正但保留明显残余，
  /// 避免把真实动作内容整帧拉回）。
  func testProcessFlagsExcessiveTranslationDrift() throws {
    let canvas = 256
    let frames = try [
      CGRect(x: 88, y: 48, width: 80, height: 140),
      CGRect(x: 88, y: 48, width: 80, height: 140),
      CGRect(x: 118, y: 48, width: 80, height: 140),
    ].map { rect -> CGImage in
      guard
        let frame = makeFrame(
          width: canvas, height: canvas, background: (0, 1, 0), subjectRect: rect)
      else { throw NSError(domain: "test", code: 1) }
      return frame
    }

    let result = try PoseFrameSetProcessor.process(images: frames)

    XCTAssertTrue(
      result.diagnostics.exceedsDriftThreshold,
      "44.6 单元像素的质心偏移应超过 18px 告警阈值")
    guard let boxBase = subjectBBox(in: result.cells[0]),
      let boxDrifted = subjectBBox(in: result.cells[2])
    else {
      return XCTFail("cells should contain a subject")
    }
    let remainingShift = abs(boxDrifted.minX - boxBase.minX)
    XCTAssertLessThan(
      remainingShift, 40, "夹紧矫正应消掉一部分漂移（原始 44.6 单元像素）")
    XCTAssertGreaterThan(
      remainingShift, 20, "超出夹紧范围的残余应保留（避免整帧重定位）")
  }

  /// 背景统一估计：三帧背景色调各异（模拟 AI 逐帧生成的色调漂移），
  /// 处理后所有单元背景都应完全透明、主体保持不透明。
  func testProcessUnifiesBackgroundEstimationAcrossFrames() throws {
    let canvas = 256
    let backgrounds: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
      (0, 1, 0), (0, 0.92, 0.04), (0.03, 1, 0),
    ]
    let frames = try backgrounds.map { background -> CGImage in
      guard
        let frame = makeFrame(
          width: canvas, height: canvas, background: background,
          subjectRect: CGRect(x: 88, y: 48, width: 80, height: 140))
      else { throw NSError(domain: "test", code: 1) }
      return frame
    }

    let result = try PoseFrameSetProcessor.process(images: frames)

    XCTAssertEqual(result.cells.count, 3)
    for cell in result.cells {
      let corner = Self.pixel(in: cell, x: 2, y: 2)
      XCTAssertEqual(corner.a, 0, "keyed background corner should be transparent")
      // 80×140 主体 contain-fit 后正好撑满单元全高，顶部无背景；
      // 背景探针取主体水平范围外（主体缩放后约横跨 x 36..156）。
      let topEdge = Self.pixel(in: cell, x: 170, y: 1)
      XCTAssertEqual(topEdge.a, 0, "keyed background edge should be transparent")
      guard let box = subjectBBox(in: cell) else {
        return XCTFail("cell should contain a subject")
      }
      let center = Self.pixel(
        in: cell, x: Int(box.midX), y: Int(box.midY))
      XCTAssertGreaterThan(center.a, 200, "subject should stay opaque")
    }
  }

  /// 某一帧没有主体（纯背景）应报出帧序号，便于用户定位重新生成。
  func testProcessThrowsWithFrameIndexOnEmptySubject() throws {
    let canvas = 256
    guard
      let good = makeFrame(
        width: canvas, height: canvas, background: (0, 1, 0),
        subjectRect: CGRect(x: 88, y: 48, width: 80, height: 140)),
      let empty = makeFrame(
        width: canvas, height: canvas, background: (0, 1, 0),
        subjectRect: .zero)
    else { throw NSError(domain: "test", code: 1) }

    XCTAssertThrowsError(try PoseFrameSetProcessor.process(images: [good, empty])) { error in
      XCTAssertEqual(
        error as? PoseFrameSetError, .emptySubject(frameIndex: 1))
    }
  }

  private static func pixel(
    in cell: CGImage, x: Int, y: Int
  ) -> (r: Int, g: Int, b: Int, a: Int) {
    guard
      let cropped = cell.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
      let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let data = context.data
    else { return (0, 0, 0, 0) }
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let bytes = data.bindMemory(to: UInt8.self, capacity: 4)
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
  }
}
