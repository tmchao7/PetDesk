import CoreGraphics
import Foundation

/// 一组姿势帧相对首帧的漂移指标（对齐前测量，量化生成端一致性）。
/// 阈值参考 OpenAI Codex hatch-pet 精灵图验收标准（面积比 ≤ 1.26、
/// 质心偏移 ≤ 18 单元像素）。
public struct PoseFrameDiagnostics: Sendable, Equatable {
  public struct FrameDrift: Sendable, Equatable {
    /// 强主体像素数相对首帧的面积比。
    public let areaRatio: Double
    /// 强主体质心相对首帧的偏移（单元像素）。
    public let centroidShift: CGFloat

    public init(areaRatio: Double, centroidShift: CGFloat) {
      self.areaRatio = areaRatio
      self.centroidShift = centroidShift
    }
  }

  /// 面积比告警上限（越界视为体型/镜头漂移）。
  public static let areaRatioLimit = 1.26
  /// 质心偏移告警上限（192×208 单元像素）。
  public static let centroidShiftLimit: CGFloat = 18

  /// 逐帧漂移指标；第 0 帧为基准（1.0 / 0）。
  public let frames: [FrameDrift]

  public init(frames: [FrameDrift]) {
    self.frames = frames
  }

  /// 任一帧面积比越出 [1/1.26, 1.26] 或质心偏移超 18px 时为 true。
  public var exceedsDriftThreshold: Bool {
    frames.dropFirst().contains {
      $0.areaRatio > Self.areaRatioLimit || $0.areaRatio < 1 / Self.areaRatioLimit
        || $0.centroidShift > Self.centroidShiftLimit
    }
  }

  /// 首个超阈值帧的序号（用于提示文案）；无则 nil。
  public var firstDriftedFrameIndex: Int? {
    for (offset, frame) in frames.dropFirst().enumerated()
    where frame.areaRatio > Self.areaRatioLimit || frame.areaRatio < 1 / Self.areaRatioLimit
      || frame.centroidShift > Self.centroidShiftLimit
    {
      return offset + 1
    }
    return nil
  }
}

/// 一组姿势帧导入错误（带帧序号，便于用户定位重新生成）。
public enum PoseFrameSetError: Error, Equatable, Sendable {
  /// 该帧没有识别到主体（纯背景）。
  case emptySubject(frameIndex: Int)
  /// 位图上下文创建失败（极端内存压力）。
  case contextUnavailable(frameIndex: Int)
}

/// 跨帧归一化的处理结果。
public struct PoseFrameSetResult: Sendable {
  public let cells: [CGImage]
  public let diagnostics: PoseFrameDiagnostics

  public init(cells: [CGImage], diagnostics: PoseFrameDiagnostics) {
    self.cells = cells
    self.diagnostics = diagnostics
  }
}

/// 把同一状态的一组姿势帧（1~8 张 AI 生成动作帧）处理成 192×208 透明动画单元，
/// 并做跨帧归一化——消除“逐帧独立处理”放大的漂移：
///
/// 1. **统一背景估计**：整组帧用同一个背景色（各帧边缘中位数的逐通道中位数）
///    抠底，帧间色调漂移不再导致抠图结果不一致；
/// 2. **统一缩放**：所有帧共用一个缩放（最大包围盒决定），任何帧不被放大，
///    逐帧 contain-fit 造成的“忽大忽小”消失；
/// 3. **统一锚点**：水平按强主体质心中位数、垂直按包围盒底边基线（地面）
///    中位数对齐；±18 单元像素内的平移被完全矫正（消除“忽左忽右”），
///    超出部分保留（可能是真实动作内容），并计入漂移诊断；
/// 4. **漂移诊断**：逐帧面积比与质心偏移（对齐前测量），供 UI 提示
///    “第 N 帧与首帧差异较大”。
public enum PoseFrameSetProcessor {
  /// 超出该范围（单元像素）的平移被视为可能的动作内容，只矫正 18px。
  private static let maxCorrection: CGFloat = 18

  public static func process(
    images: [CGImage], chromaTolerance: CGFloat = 0.18
  ) throws -> PoseFrameSetResult {
    guard !images.isEmpty else {
      throw PoseFrameSetError.emptySubject(frameIndex: 0)
    }

    // 1. 预备位图 + 逐帧边缘中位数背景。
    var bitmaps: [PoseCellProcessor.PoseFrameBitmap] = []
    bitmaps.reserveCapacity(images.count)
    for (index, image) in images.enumerated() {
      guard let bitmap = PoseCellProcessor.prepareFrame(image) else {
        throw PoseFrameSetError.contextUnavailable(frameIndex: index)
      }
      bitmaps.append(bitmap)
    }
    let opaqueMedians =
      bitmaps
      .filter { !$0.hasTransparentBackground }
      .map { PoseCellProcessor.edgeMedianBackground($0) }
    let groupBackground: (r: CGFloat, g: CGFloat, b: CGFloat)? =
      opaqueMedians.isEmpty
      ? nil
      : (
        r: median(opaqueMedians.map { $0.r }),
        g: median(opaqueMedians.map { $0.g }),
        b: median(opaqueMedians.map { $0.b })
      )

    // 2. 整组统一背景抠底。
    var keyed: [PoseCellProcessor.KeyedPoseFrame] = []
    keyed.reserveCapacity(bitmaps.count)
    for (index, bitmap) in bitmaps.enumerated() {
      let background: (r: CGFloat, g: CGFloat, b: CGFloat)
      if bitmap.hasTransparentBackground {
        background = (r: 0, g: 0, b: 0)
      } else if let groupBackground {
        background = groupBackground
      } else {
        background = PoseCellProcessor.edgeMedianBackground(bitmap)
      }
      guard
        let frame = PoseCellProcessor.keyFrame(
          bitmap, background: background, chromaTolerance: chromaTolerance)
      else {
        throw PoseFrameSetError.emptySubject(frameIndex: index)
      }
      keyed.append(frame)
    }

    // 3. 逐帧 99.8% 质量窗口收紧包围盒（统一规则；单帧 makeCell 是条件收紧，
    //    多帧必须统一语义，否则带场景尾巴的帧会被单独放大造成帧间跳变）。
    let boxes: [CGRect] = keyed.map { frame in
      let rowWindow = PoseCellProcessor.massWindow(
        frame.strongRowDensity,
        total: frame.strongTotal,
        low: 0.001,
        high: 0.999,
        fallbackMin: frame.minRow,
        fallbackMax: frame.maxRow
      )
      let columnWindow = PoseCellProcessor.massWindow(
        frame.strongColumnDensity,
        total: frame.strongTotal,
        low: 0.001,
        high: 0.999,
        fallbackMin: frame.minColumn,
        fallbackMax: frame.maxColumn
      )
      return CGRect(
        x: columnWindow.min,
        y: rowWindow.min,
        width: columnWindow.max - columnWindow.min + 1,
        height: rowWindow.max - rowWindow.min + 1
      )
    }

    // 4. 统一缩放：最大包围盒决定，任何帧不被放大。
    let cellWidth = SpriteSheetSpec.frameWidth
    let cellHeight = SpriteSheetSpec.frameHeight
    let scale = boxes.reduce(CGFloat.greatestFiniteMagnitude) { current, box in
      min(current, min(cellWidth / box.width, cellHeight / box.height))
    }

    // 5. 锚点：水平 = 强主体质心中位数；垂直 = 包围盒底边（地面）中位数。
    let anchorX = median(keyed.map { CGFloat($0.strongCentroid.x) })
    let anchorBottom = median(boxes.map { $0.maxY })

    // 6. 漂移诊断（对齐前、缩放到单元空间）。
    let reference = keyed[0]
    let diagnostics = PoseFrameDiagnostics(
      frames: keyed.enumerated().map { index, frame in
        let areaRatio: Double
        if reference.strongTotal > 0 {
          areaRatio = Double(frame.strongTotal) / Double(reference.strongTotal)
        } else {
          let referenceArea = max(1, boxes[0].width * boxes[0].height)
          areaRatio = Double(boxArea(boxes[index])) / Double(referenceArea)
        }
        let shift = hypot(
          (CGFloat(frame.strongCentroid.x) - CGFloat(reference.strongCentroid.x)) * scale,
          (CGFloat(frame.strongCentroid.y) - CGFloat(reference.strongCentroid.y)) * scale
        )
        return PoseFrameDiagnostics.FrameDrift(
          areaRatio: areaRatio, centroidShift: shift)
      })

    // 7. 统一缩放 + 锚点渲染进 192×208 单元。
    // 最高的帧垂直居中（与单帧 contain-fit 观感一致），其余帧底边对齐同一地面。
    let maxScaledHeight = boxes.reduce(CGFloat(0)) { max($0, $1.height * scale) }
    let baselineY = cellHeight / 2 + maxScaledHeight / 2
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    var cells: [CGImage] = []
    cells.reserveCapacity(keyed.count)
    for (index, frame) in keyed.enumerated() {
      let box = boxes[index]
      guard
        let source = frame.context.makeImage(),
        let cropped = source.cropping(to: box)
      else {
        throw PoseFrameSetError.contextUnavailable(frameIndex: index)
      }
      let scaledWidth = box.width * scale
      let scaledHeight = box.height * scale
      let residualX = (CGFloat(frame.strongCentroid.x) - anchorX) * scale
      let residualBottom = (box.maxY - anchorBottom) * scale
      // 夹紧到单元内（缩放已保证 destW/destH ≤ cell，夹紧只影响锚点越界部分）。
      let destLeft = max(
        0, min(cellWidth / 2 + correction(residualX) - scaledWidth / 2, cellWidth - scaledWidth))
      let destTop = max(
        0, min(baselineY + correction(residualBottom) - scaledHeight, cellHeight - scaledHeight))
      guard
        let cellContext = CGContext(
          data: nil,
          width: Int(cellWidth),
          height: Int(cellHeight),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: bitmapInfo.rawValue
        )
      else {
        throw PoseFrameSetError.contextUnavailable(frameIndex: index)
      }
      cellContext.clear(CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
      cellContext.interpolationQuality = .high
      // CGContext 绘制坐标原点在左下：视觉 y 向下的 destTop 需翻转。
      cellContext.draw(
        cropped,
        in: CGRect(
          x: destLeft,
          y: cellHeight - destTop - scaledHeight,
          width: scaledWidth,
          height: scaledHeight
        )
      )
      guard let drawn = cellContext.makeImage() else {
        throw PoseFrameSetError.contextUnavailable(frameIndex: index)
      }
      guard
        let cell = PoseCellProcessor.defringeAndFeather(
          drawn,
          chromaBackground: bitmaps[index].hasTransparentBackground
            ? nil : groupBackground
        )
      else {
        throw PoseFrameSetError.contextUnavailable(frameIndex: index)
      }
      cells.append(cell)
    }

    return PoseFrameSetResult(cells: cells, diagnostics: diagnostics)
  }

  /// 锚点矫正：±18 单元像素内的平移完全取消；超出部分保留（可能的动作内容）。
  private static func correction(_ residual: CGFloat) -> CGFloat {
    let clamped = max(-maxCorrection, min(maxCorrection, residual))
    return residual - clamped
  }

  private static func median(_ values: [CGFloat]) -> CGFloat {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  private static func boxArea(_ box: CGRect) -> Int {
    Int(box.width) * Int(box.height)
  }
}
