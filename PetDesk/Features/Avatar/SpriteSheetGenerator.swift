import CoreGraphics
import Foundation

/// 程序化精灵图生成器（Codex Pet 级别）：
/// 对单张头像做确定性微变换生成 8 行动画帧，
/// 动作幅度刻意保持微妙（位移 1-2px、旋转 1-2°），不喧哗。
public enum SpriteSheetGenerator {
  /// 帧内变换参数。
  private struct FrameTransform {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var rotation: CGFloat = 0  // 弧度
    var blink = false
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
    // 底部对齐：角色站在画面底部（y 从 0 开始）。
    context.draw(source, in: CGRect(x: 0, y: 0, width: frameW, height: frameW))
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
    context.rotate(by: transform.rotation)
    context.translateBy(x: -cx, y: -cy)
    context.draw(base, in: baseRect)

    // 眨眼：在眼睛区域覆盖半透明肤色带（Codex 的 -colorize 70% 等效）。
    if transform.blink {
      let eyeRect = CGRect(x: 48, y: 60, width: 96, height: 10)
      context.saveGState()
      context.clip(to: eyeRect)
      context.setFillColor(
        CGColor(red: 0.957, green: 0.902, blue: 0.847, alpha: 0.7)
      )
      context.fill(CGRect(x: 0, y: 0, width: baseRect.width, height: baseRect.height))
      context.restoreGState()
    }
    context.restoreGState()
  }
}
