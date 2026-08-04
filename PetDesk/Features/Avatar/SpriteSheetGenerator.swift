import CoreGraphics
import Foundation

/// 程序化精灵图生成器（Codex Pet 级别）：
/// 对单张头像（或每行一个 AI 姿态单元）做确定性微变换生成 8 行动画帧，
/// 动作幅度刻意保持微妙（位移 1-2px、旋转 1-2°），不喧哗。
public enum SpriteSheetGenerator {
  /// 帧内变换参数。
  private struct FrameTransform {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var rotation: CGFloat = 0  // 弧度
    var blink = false
  }

  /// 无外部定位时的默认眨眼遮罩（192 宽基准坐标，原点左下）。
  private static let defaultEyeBand = CGRect(x: 48, y: 60, width: 96, height: 10)

  /// 从一张方形头像生成完整精灵图（8 行 × 8 列，192×208/帧）。
  /// - Parameter eyeBandInSource: 眼睛区域在源图像像素坐标中的位置（原点左下，
  ///   与 Core Graphics 一致）；为 nil 时使用固定默认遮罩。
  public static func generate(from source: CGImage, eyeBandInSource: CGRect? = nil) -> CGImage? {
    guard let base = fittedBase(from: source) else { return nil }
    guard let cell = containingCell(base) else { return nil }
    let eyeBand =
      eyeBandInSource.map {
        scaledEyeBand($0, imageWidth: source.width, imageHeight: source.height)
      }
      ?? defaultEyeBand
    let rowFrames = Dictionary(
      uniqueKeysWithValues: AnimationRow.allCases.map { ($0, [cell]) }
    )
    return assemble(
      rowFrames: rowFrames,
      fallbackCell: cell,
      transformsEnabled: true,
      eyeBandInCell: eyeBand
    )
  }

  /// 从每行一个基础单元（192×208，透明背景）生成完整精灵图（AI 姿态管线入口）。
  /// 每行单单元 + 程序化微变换循环 8 列（默认头像与 AI 生成路径）。
  /// - Parameter eyeBandInCell: 眼睛遮罩在单元坐标中的位置；nil 使用默认遮罩。
  public static func generate(
    fromRowCells rowCells: [AnimationRow: CGImage],
    eyeBandInCell: CGRect? = nil
  ) -> CGImage? {
    guard let anyCell = rowCells.first?.value else { return nil }
    let frames = Dictionary(uniqueKeysWithValues: rowCells.map { ($0.key, [$0.value]) })
    return assemble(
      rowFrames: frames,
      fallbackCell: anyCell,
      transformsEnabled: true,
      eyeBandInCell: eyeBandInCell ?? defaultEyeBand
    )
  }

  /// 从每行一个或多个用户姿势帧生成完整精灵图（姿势导入入口）。
  /// - 自定义行（单帧或多帧）：第 0..<N 列按帧序原样填入（不叠加微变换），
  ///   剩余列用 fallbackCell 补位——保证重启后 sync 能从"遇到基准单元即停"
  ///   精确恢复帧数（单帧行恢复 1 帧、多帧行恢复 N 帧）。
  /// - 缺失行：使用 fallbackCell（走程序化微变换，与默认头像一致）。
  /// - Parameter fallbackCell: 头像基准单元，作为补位与缺失行回退。
  public static func generate(
    fromRowFrames rowFrames: [AnimationRow: [CGImage]],
    fallbackCell: CGImage,
    eyeBandInCell: CGRect? = nil
  ) -> CGImage? {
    assemble(
      rowFrames: rowFrames,
      fallbackCell: fallbackCell,
      transformsEnabled: false,
      eyeBandInCell: eyeBandInCell ?? defaultEyeBand
    )
  }

  /// 从方形头像生成底部对齐的 192×208 基准单元（供逐行姿势混合组装使用）。
  public static func baseCell(from source: CGImage) -> CGImage? {
    guard let base = fittedBase(from: source) else { return nil }
    return containingCell(base)
  }

  private static func assemble(
    rowFrames: [AnimationRow: [CGImage]],
    fallbackCell: CGImage,
    transformsEnabled: Bool,
    eyeBandInCell: CGRect
  ) -> CGImage? {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    let rows = AnimationRow.allCases
    let sheetW = frameW * SpriteSheetSpec.columns
    let sheetH = frameH * rows.count

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: sheetW,
        height: sheetH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    context.interpolationQuality = .high

    for (rowIndex, row) in rows.enumerated() {
      let frames = rowFrames[row] ?? [fallbackCell]
      let origin = CGPoint(
        x: 0,
        y: (rows.count - 1 - rowIndex) * frameH  // 精灵图 y 轴向下，CoreGraphics 向上
      )
      // 走程序化微变换的条件：显式启用（默认/AI 入口），或用户入口下该行
      // 是未设置行（单帧且与 fallbackCell 引用相同 = 默认头像单元）——
      // 后者保留默认行的微动帧，避免导入姿势后其他行退化为单帧。
      let useTransforms =
        transformsEnabled
        || (frames.count == 1 && isSameReference(frames[0], fallbackCell))
      if useTransforms {
        // 默认/AI 行：单单元 + 程序化微变换循环 8 列。
        let cell = frames[0]
        for col in 0..<SpriteSheetSpec.columns {
          let transform = transforms(for: row, frame: col)
          drawFrame(
            cell,
            at: CGPoint(x: CGFloat(col * frameW), y: origin.y),
            transform: transform,
            eyeBand: eyeBandInCell,
            context: context
          )
        }
      } else {
        // 用户姿势行（单帧或多帧）：帧按序填入，剩余列用基准单元补位，
        // 不叠加程序化微变换（动作帧本身是完整动作）。
        for col in 0..<SpriteSheetSpec.columns {
          let cell = col < frames.count ? frames[col] : fallbackCell
          drawFrame(
            cell,
            at: CGPoint(x: CGFloat(col * frameW), y: origin.y),
            transform: FrameTransform(),
            eyeBand: eyeBandInCell,
            context: context
          )
        }
      }
    }

    return context.makeImage()
  }

  /// CGImage 引用相等判断（用于区分"默认头像单元"与"用户导入单元"）。
  private static func isSameReference(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
    Unmanaged.passUnretained(lhs).toOpaque() == Unmanaged.passUnretained(rhs).toOpaque()
  }

  /// 每行每帧的确定性变换（Codex Pet build_row 风格）。
  private static func transforms(for row: AnimationRow, frame: Int) -> FrameTransform {
    switch row {
    case .idle:
      // base base blink base base blink — 呼吸 + 眨眼
      let y = [0, -1, 0, 0, -1, 0]
      let blink = [false, false, true, false, false, true]
      return FrameTransform(
        offsetY: CGFloat(y[frame % y.count]),
        blink: blink[frame % blink.count]
      )
    case .walking:
      // 走路：左右平移 + 上下起伏（Codex running-right 序列）
      let x = [0, 1, 2, 1, 0, -1, -2, -1]
      let y = [0, 0, -1, 0, 0, 0, -1, 0]
      return FrameTransform(
        offsetX: CGFloat(x[frame % x.count]),
        offsetY: CGFloat(y[frame % y.count])
      )
    case .running:
      // 跑步：更大平移 + 前倾
      let x = [0, 2, 4, 2, 0, -2, -4, -2]
      let y = [0, -1, -2, -1, 0, 0, -1, 0]
      let r = [0, 0.02, 0.03, 0.02, 0, -0.02, -0.03, -0.02]
      return FrameTransform(
        offsetX: CGFloat(x[frame % x.count]),
        offsetY: CGFloat(y[frame % y.count]),
        rotation: CGFloat(r[frame % r.count])
      )
    case .working:
      // 工作：轻微上下节奏（Codex running-active 节奏）
      let y = [0, -1, 0, -1, 0, -1]
      return FrameTransform(offsetY: CGFloat(y[frame % y.count]))
    case .drinking:
      // 喝茶：点头（Codex waiting 序列）
      let y = [0, 0, -1, 0, 0, 1]
      return FrameTransform(offsetY: CGFloat(y[frame % y.count]))
    case .sleeping:
      // 睡觉：侧躺微转
      let r = [0, -0.04, -0.07, -0.04, 0, 0]
      return FrameTransform(rotation: CGFloat(r[frame % r.count]))
    case .happy:
      // 开心：跳跃弧线（Codex jumping 序列）
      let y = [2, 0, -8, -2, 0]
      return FrameTransform(offsetY: CGFloat(y[frame % y.count]))
    case .surprised:
      // 惊讶：抖动 + 眨眼
      let r = [-0.03, 0.03, -0.03, 0.03]
      let blink = [true, false, true, false]
      return FrameTransform(
        rotation: CGFloat(r[frame % r.count]),
        blink: blink[frame % blink.count]
      )
    }
  }

  /// 把方形头像缩放到底部对齐的 192×192 区域（保持比例，居中）。
  private static func fittedBase(from source: CGImage) -> CGImage? {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: frameW,
        height: frameW,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: frameW, height: frameW))
    context.interpolationQuality = .high
    // 底部对齐：角色站在画面底部（y 从 0 开始）。
    context.draw(source, in: CGRect(x: 0, y: 0, width: frameW, height: frameW))
    return context.makeImage()
  }

  /// 把 192×192 的方形基准帧放进底部对齐的 192×208 透明单元。
  private static func containingCell(_ base: CGImage) -> CGImage? {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: frameW,
        height: frameH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: frameW, height: frameH))
    context.interpolationQuality = .high
    context.draw(base, in: CGRect(x: 0, y: 0, width: frameW, height: frameW))
    return context.makeImage()
  }

  /// 把源图像坐标中的遮罩等比缩放到 192 宽的基准坐标。
  private static func scaledEyeBand(
    _ rect: CGRect,
    imageWidth: Int,
    imageHeight: Int
  ) -> CGRect {
    let scaleX = SpriteSheetSpec.frameWidth / CGFloat(imageWidth)
    let scaleY = SpriteSheetSpec.frameWidth / CGFloat(imageHeight)
    return CGRect(
      x: rect.minX * scaleX,
      y: rect.minY * scaleY,
      width: rect.width * scaleX,
      height: rect.height * scaleY
    )
  }

  private static func drawFrame(
    _ cell: CGImage,
    at origin: CGPoint,
    transform: FrameTransform,
    eyeBand: CGRect,
    context: CGContext
  ) {
    let frameRect = CGRect(
      x: 0,
      y: 0,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    // 绕帧中心应用变换。
    let cx = frameRect.midX
    let cy = frameRect.midY
    context.translateBy(x: cx + transform.offsetX, y: cy + transform.offsetY)
    context.rotate(by: transform.rotation)
    context.translateBy(x: -cx, y: -cy)
    context.draw(cell, in: frameRect)

    // 眨眼：在眼睛区域覆盖半透明肤色带（Codex 的 -colorize 70% 等效）。
    if transform.blink {
      context.saveGState()
      context.clip(to: eyeBand)
      context.setFillColor(
        CGColor(red: 0.957, green: 0.902, blue: 0.847, alpha: 0.7)
      )
      context.fill(frameRect)
      context.restoreGState()
    }
    context.restoreGState()
  }
}
