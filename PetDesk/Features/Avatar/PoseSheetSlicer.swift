import CoreGraphics
import Foundation

/// 横向帧条带自动切帧：AI 在**单次生成**里输出“N 帧横向长图”是角色一致性
/// 最好的生成方式（同一次生成天然同角色、同画风、同色调），导入时自动切分
/// 为 N 帧，兑现提示词文档承诺的“长图切帧”工作流。
///
/// 判定纪律：宁可回退单帧，不可错切。宽幅但不是条带的图（横躺角色、
/// 16:9 插画）必须原样返回：
/// 1. 几何：宽高比 ≥ 1.8，且宽度在 N·高度 的 15% 容差内（N = 2...8）；
/// 2. 逐格校验：每格边缘接近纯色（或自带透明），格内有可见主体——
///    主体横跨切线的宽图、含空格的假条带都会被拒绝。
public enum PoseSheetSlicer {
  /// 切线垂直边的背景占比阈值：低于视为“切线穿过主体”，拒绝切分。
  static let cutEdgeBackgroundFraction: Double = 0.9
  /// 单格内部主体像素占比下限：低于视为空格，拒绝切分。
  static let cellSubjectFraction: Double = 0.03
  /// 宽高比达到该值才可能是条带（普通 16:9 / 3:2 构图远低于此）。
  static let minimumAspectRatio: CGFloat = 1.8
  /// 宽度与 N·高度的容差比例（允许小的边距/缝隙）。
  static let widthTolerance: Double = 0.15

  /// 检测横向帧条带并切分；判定不通过时返回原图（单帧导入路径）。
  public static func sliceStrip(from image: CGImage) -> [CGImage] {
    let width = image.width
    let height = image.height
    guard height > 0 else { return [image] }
    let ratio = CGFloat(width) / CGFloat(height)
    guard ratio >= minimumAspectRatio else { return [image] }
    let frameCount = Int(ratio.rounded())
    guard frameCount >= 2, frameCount <= SpriteSheetSpec.columns else { return [image] }
    let expectedWidth = frameCount * height
    guard
      abs(width - expectedWidth) <= Int(Double(height) * widthTolerance)
    else { return [image] }

    var cells: [CGImage] = []
    cells.reserveCapacity(frameCount)
    // 整数切分边界（CGImage.cropping 需要整数 rect；均分误差 ≤ 1px）。
    var boundaries: [Int] = []
    for index in 0...frameCount {
      boundaries.append(Int((CGFloat(width) * CGFloat(index) / CGFloat(frameCount)).rounded()))
    }
    for index in 0..<frameCount {
      let rect = CGRect(
        x: boundaries[index], y: 0,
        width: boundaries[index + 1] - boundaries[index], height: height
      )
      guard let cell = image.cropping(to: rect) else { return [image] }
      // 只校验切线两侧的垂直边：外边界允许主体贴边（角色脚踩画布底边很常见），
      // 但切线必须接近纯背景——主体横跨切线说明这不是条带，切开会切断角色。
      guard
        cellLooksLikeFrame(
          cell,
          checkLeftCut: index > 0,
          checkRightCut: index < frameCount - 1
        )
      else { return [image] }
      cells.append(cell)
    }
    return cells
  }

  /// 单格校验：切线垂直边接近纯背景（或透明，背景占比 ≥ 90%）且格内有可见
  /// 主体（≥ 3%，拒绝空格假条带）。
  static func cellLooksLikeFrame(
    _ cell: CGImage, checkLeftCut: Bool, checkRightCut: Bool
  ) -> Bool {
    let width = cell.width
    let height = cell.height
    guard width > 1, height > 1 else { return false }
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
    else { return false }
    context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)
    let stride = max(1, height / 128)

    /// 一条垂直边的背景占比：透明像素即背景；不透明像素与该边中位数色
    /// 距离 < 0.18 视为背景。主体横跨切线时该边会出现成带的主题色像素，
    /// 占比骤降。
    func cutEdgeIsBackground(_ x: Int) -> Bool {
      var total = 0
      var backgroundCount = 0
      var reds: [Int] = []
      var greens: [Int] = []
      var blues: [Int] = []
      for row in Swift.stride(from: 0, to: height, by: stride) {
        let offset = row * context.bytesPerRow + x * 4
        total += 1
        if Int(bytes[offset + 3]) < 8 {
          backgroundCount += 1
          continue
        }
        reds.append(Int(bytes[offset]))
        greens.append(Int(bytes[offset + 1]))
        blues.append(Int(bytes[offset + 2]))
      }
      guard total > 0 else { return false }
      if reds.isEmpty {
        return Double(backgroundCount) / Double(total) >= cutEdgeBackgroundFraction
      }
      func median(_ values: [Int]) -> CGFloat {
        let sorted = values.sorted()
        return CGFloat(sorted[sorted.count / 2])
      }
      let edgeBackground = (
        r: median(reds), g: median(greens), b: median(blues)
      )
      var nearBackgroundCount = backgroundCount
      for (index, red) in reds.enumerated() {
        let dr = (CGFloat(red) - edgeBackground.r) / 255
        let dg = (CGFloat(greens[index]) - edgeBackground.g) / 255
        let db = (CGFloat(blues[index]) - edgeBackground.b) / 255
        let distance = sqrt(dr * dr + dg * dg + db * db) / PoseCellProcessor.maxRGBDistance
        if distance < 0.18 {
          nearBackgroundCount += 1
        }
      }
      return Double(nearBackgroundCount) / Double(total) >= cutEdgeBackgroundFraction
    }

    if checkLeftCut, !cutEdgeIsBackground(0) { return false }
    if checkRightCut, !cutEdgeIsBackground(width - 1) { return false }

    // 内部主体占比（避开 1px 边缘）：拒绝“整格纯背景”的假条带。
    // 主体 = 透明像素之外、与边缘背景色明显不同的像素——不透明背景
    // （绿幕/纯色底）的空格不能因“整格不透明”被误判为有主体。
    /// 四边不透明像素的逐通道中位数，作为该格背景色估计；全透明边返回 nil。
    func borderBackgroundColor() -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
      var reds: [Int] = []
      var greens: [Int] = []
      var blues: [Int] = []
      let edgeStride = max(1, max(width, height) / 128)
      func sample(_ offset: Int) {
        if Int(bytes[offset + 3]) >= 8 {
          reds.append(Int(bytes[offset]))
          greens.append(Int(bytes[offset + 1]))
          blues.append(Int(bytes[offset + 2]))
        }
      }
      for row in Swift.stride(from: 0, to: height, by: edgeStride) {
        sample(row * context.bytesPerRow)
        sample(row * context.bytesPerRow + (width - 1) * 4)
      }
      for column in Swift.stride(from: 0, to: width, by: edgeStride) {
        sample(column * 4)
        sample((height - 1) * context.bytesPerRow + column * 4)
      }
      guard !reds.isEmpty else { return nil }
      func median(_ values: [Int]) -> CGFloat {
        let sorted = values.sorted()
        return CGFloat(sorted[sorted.count / 2])
      }
      return (r: median(reds), g: median(greens), b: median(blues))
    }
    let backgroundColor = borderBackgroundColor()
    let interiorStride = max(1, min(width, height) / 128)
    var interiorTotal = 0
    var interiorSubject = 0
    for row in Swift.stride(from: 1, to: height - 1, by: interiorStride) {
      for column in Swift.stride(from: 1, to: width - 1, by: interiorStride) {
        let offset = row * context.bytesPerRow + column * 4
        interiorTotal += 1
        if Int(bytes[offset + 3]) < 8 { continue }
        if let backgroundColor {
          let dr = (CGFloat(bytes[offset]) - backgroundColor.r) / 255
          let dg = (CGFloat(bytes[offset + 1]) - backgroundColor.g) / 255
          let db = (CGFloat(bytes[offset + 2]) - backgroundColor.b) / 255
          let distance = sqrt(dr * dr + dg * dg + db * db) / PoseCellProcessor.maxRGBDistance
          if distance < 0.18 { continue }
        }
        interiorSubject += 1
      }
    }
    guard interiorTotal > 0 else { return false }
    return Double(interiorSubject) / Double(interiorTotal) >= cellSubjectFraction
  }
}
