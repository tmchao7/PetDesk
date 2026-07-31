import CoreGraphics
import Foundation

/// 程序化精灵图生成器：对单张头像做确定性微变换，
/// 生成 8 行动画帧（每行一种动作）并打包为精灵图。
public enum SpriteSheetGenerator {
  /// 帧内变换参数。
  private struct FrameTransform {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: CGFloat = 0  // 弧度
  }

  /// 从一张方形头像生成完整精灵图（8 行 × 8 列，192×208/帧）。
  public static func generate(from source: CGImage) -> CGImage? {
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

    // 基准帧：方形头像 aspectFit 到底部对齐的 192×192 区域。
    let baseImage = fittedBase(from: source)
    guard let baseImage else { return nil }
    let baseRect = CGRect(x: 0, y: 0, width: frameW, height: frameH)

    for (rowIndex, row) in rows.enumerated() {
      for col in 0..<SpriteSheetSpec.columns {
        let transform = transforms(for: row, frame: col)
        let origin = CGPoint(
          x: col * frameW,
          y: (rows.count - 1 - rowIndex) * frameH  // 精灵图 y 轴向下，CoreGraphics 向上
        )
        drawFrame(
          baseImage,
          in: baseRect,
          at: origin,
          transform: transform,
          context: context
        )
      }
    }

    return context.makeImage()
  }

  /// 每行每帧的确定性变换。
  private static func transforms(for row: AnimationRow, frame: Int) -> FrameTransform {
    var t = FrameTransform()
    switch row {
    case .idle:
      // 呼吸浮动 + 轻微左右摇摆
      let y = [0, -2, -4, -2, 0, 2]
      let x = [0, 1, 0, -1, 0, 1]
      t.offsetY = CGFloat(y[frame % y.count])
      t.offsetX = CGFloat(x[frame % x.count])
    case .walking:
      // 走路：上下起伏 + 前后摇摆
      let y = [0, -5, -2, 3, 0, -5, -2, 3]
      let r = [0, 0.04, 0.02, -0.03, 0, 0.04, 0.02, -0.03]
      t.offsetY = CGFloat(y[frame % y.count])
      t.rotation = CGFloat(r[frame % r.count])
    case .running:
      // 跑步：大幅起伏 + 前倾 + 压扁拉伸
      let y = [0, -8, -3, 5, 0, -8, -3, 5]
      let sy = [1, 0.92, 1.05, 1.1, 1, 0.92, 1.05, 1.1]
      t.offsetY = CGFloat(y[frame % y.count])
      t.scaleY = CGFloat(sy[frame % sy.count])
      t.rotation = 0.05
    case .working:
      // 工作：小幅度敲击节奏
      let y = [0, -3, 0, 2, 0, -2]
      let r = [0, 0.02, 0, -0.02, 0, 0.01]
      t.offsetY = CGFloat(y[frame % y.count])
      t.rotation = CGFloat(r[frame % r.count])
    case .drinking:
      // 喝茶：小幅上下 + 点头
      let y = [0, 1, 2, 0, -1, 0]
      let r = [0, 0.015, 0.03, 0, -0.02, 0]
      t.offsetY = CGFloat(y[frame % y.count])
      t.rotation = CGFloat(r[frame % r.count])
    case .sleeping:
      // 睡觉：侧躺（旋转）+ 压扁
      let r = [0, -0.12, -0.24, -0.24, -0.12, 0]
      let sy = [1, 0.95, 0.88, 0.88, 0.95, 1]
      t.rotation = CGFloat(r[frame % r.count])
      t.scaleY = CGFloat(sy[frame % sy.count])
    case .happy:
      // 开心：跳跃
      let y = [0, -12, -16, -8, 0]
      t.offsetY = CGFloat(y[frame % y.count])
    case .surprised:
      // 惊讶：抖动放大
      let s = [1.06, 1.0, 1.08, 1.0]
      let r = [0.04, -0.04, 0.04, -0.04]
      t.scaleX = CGFloat(s[frame % s.count])
      t.scaleY = CGFloat(s[frame % s.count])
      t.rotation = CGFloat(r[frame % r.count])
    }
    return t
  }

  /// 把方形头像缩放到底部对齐的 192×192 区域（保持比例，居中）。
  private static func fittedBase(from source: CGImage) -> CGImage? {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    // 方形源图按宽度缩放：192×192。
    let fittedSize = CGSize(width: frameW, height: frameW)
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
    // 底部对齐：角色站在画面底部（y 从 0 开始）。
    let rect = CGRect(
      origin: CGPoint(x: 0, y: 0),
      size: fittedSize
    )
    context.draw(source, in: rect)
    return context.makeImage()
  }

  private static func drawFrame(
    _ base: CGImage,
    in baseRect: CGRect,
    at origin: CGPoint,
    transform: FrameTransform,
    context: CGContext
  ) {
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    // 绕帧中心应用变换。
    let cx = baseRect.midX
    let cy = baseRect.midY
    context.translateBy(x: cx + transform.offsetX, y: cy + transform.offsetY)
    context.scaleBy(x: transform.scaleX, y: transform.scaleY)
    context.rotate(by: transform.rotation)
    context.translateBy(x: -cx, y: -cy)
    context.draw(base, in: baseRect)
    context.restoreGState()
  }
}
