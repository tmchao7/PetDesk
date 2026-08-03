import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 单张姿势图导入错误。
public enum PoseImageImportError: Error, Sendable, Equatable {
  case unreadableImage
  case unsupportedType
  case emptySubject
}

/// 把 AI 生成的单帧姿势图处理成 192×208 透明动画单元：
/// 纯色背景自动抠底（四角采样）、裁剪到主体包围盒、contain-fit 居中。
public enum PoseCellProcessor {
  private static let maxRGBDistance = sqrt(3.0)

  /// 从 PNG/WebP 文件读取姿势图并处理成动画单元。
  public static func loadCell(from url: URL) throws -> CGImage {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw PoseImageImportError.unreadableImage
    }
    if let type = CGImageSourceGetType(source) {
      let identifier = type as String
      guard
        identifier == UTType.png.identifier || identifier == UTType.webP.identifier
      else {
        throw PoseImageImportError.unsupportedType
      }
    }
    guard let cell = makeCell(from: image) else {
      throw PoseImageImportError.emptySubject
    }
    return cell
  }

  /// - Parameter chromaTolerance: 归一化品红距离阈值（0-1），0.18 对应 ImageMagick
  ///   `-fuzz 18%`；阈值内做软抠图避免抗锯齿边缘。
  public static func makeCell(from image: CGImage, chromaTolerance: CGFloat = 0.18) -> CGImage? {
    let width = image.width
    let height = image.height
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
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let bytes = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)
    // 图片本身带透明背景（边缘有明显透明像素）时直接使用原 alpha，不做抠底。
    let hasTransparentBackground = Self.edgeIsTransparent(
      bytes: bytes,
      width: width,
      height: height,
      bytesPerRow: context.bytesPerRow
    )
    // 否则从四角采样实际背景色（色彩管理可能偏移 #FF00FF），按该色做软抠图。
    let background =
      hasTransparentBackground
      ? (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
      : Self.averageBackgroundColor(
        bytes: bytes,
        width: width,
        height: height,
        bytesPerRow: context.bytesPerRow
      )
    let inner = chromaTolerance * 0.55
    let outer = chromaTolerance

    // 每个像素的软抠 alpha（0-255）。先不动原始字节，稍后按 flood 结果统一输出。
    var alpha8 = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        let offset = row * context.bytesPerRow + column * 4
        if hasTransparentBackground {
          alpha8[row * width + column] = bytes[offset + 3]
          continue
        }
        let r = CGFloat(bytes[offset]) / 255
        let g = CGFloat(bytes[offset + 1]) / 255
        let b = CGFloat(bytes[offset + 2]) / 255
        let dr = r - background.r
        let dg = g - background.g
        let db = b - background.b
        let distance = sqrt(dr * dr + dg * dg + db * db) / maxRGBDistance

        let alpha: CGFloat
        if distance <= inner {
          alpha = 0
        } else if distance >= outer {
          alpha = 1
        } else {
          alpha = (distance - inner) / (outer - inner)
        }
        alpha8[row * width + column] = UInt8((alpha * 255).rounded())
      }
    }

    // 边缘 flood-fill 抠底：只移除与图像边缘连通的背景区域。
    // 主体内部与背景同色的部分（如哆啦A梦的白色肚皮/脸）因 flood 无法进入
    // 而被保留为不透明，避免“白色部分变透明”的问题（参考 pixa/transparent.rs
    // 与 R2beat 精灵图脚本的边缘连通策略）。
    var flood = [UInt8](repeating: 0, count: width * height)
    if !hasTransparentBackground {
      Self.floodBackground(alpha8: alpha8, flood: &flood, width: width, height: height)
    }

    // 统一输出 + 统计最终 bbox / 强主体密度。
    var minColumn = width
    var maxColumn = -1
    var minRow = height
    var maxRow = -1
    // 强主体像素（软抠底后 alpha ≥ 0.5）的行/列投影，用于收紧包围盒：
    // AI 生成图常带场景（桌面/床/渐变阴影）或角落水印，若把整幅图计入包围盒，
    // 角色会被缩放变小且位置偏移。
    var strongRowDensity = [Int](repeating: 0, count: height)
    var strongColumnDensity = [Int](repeating: 0, count: width)
    var strongTotal = 0

    for row in 0..<height {
      for column in 0..<width {
        let offset = row * context.bytesPerRow + column * 4
        let index = row * width + column
        let a = alpha8[index]
        if flood[index] == 1 {
          bytes[offset] = 0
          bytes[offset + 1] = 0
          bytes[offset + 2] = 0
          bytes[offset + 3] = 0
        } else if hasTransparentBackground {
          // 自带透明背景：像素原样保留（字节已是正确预乘）；过低的 alpha 清为 0。
          if a < 8 {
            bytes[offset] = 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
            bytes[offset + 3] = 0
          }
        } else if a < 8 {
          // 主体内部的背景色（白色肚皮等）：恢复为不透明，保留原始颜色。
          bytes[offset + 3] = 255
        } else {
          // 半透明边缘：预乘 alpha，RGB 存 color*alpha。
          let scale = CGFloat(a) / 255
          bytes[offset] = UInt8((CGFloat(bytes[offset]) * scale).rounded())
          bytes[offset + 1] = UInt8((CGFloat(bytes[offset + 1]) * scale).rounded())
          bytes[offset + 2] = UInt8((CGFloat(bytes[offset + 2]) * scale).rounded())
          bytes[offset + 3] = a
        }
        let finalAlpha = bytes[offset + 3]
        if finalAlpha > 8 {
          minColumn = min(minColumn, column)
          maxColumn = max(maxColumn, column)
          minRow = min(minRow, row)
          maxRow = max(maxRow, row)
        }
        if finalAlpha >= 128 {
          strongRowDensity[row] += 1
          strongColumnDensity[column] += 1
          strongTotal += 1
        }
      }
    }

    guard maxColumn >= minColumn, maxRow >= minRow, let processed = context.makeImage() else {
      return nil
    }

    // 保留包含中央 99.8% 强主体的行/列窗口（两侧各裁掉 0.1% 长尾）：
    // 只剔除极端稀疏的边缘杂色；窗口过窄会切到角色的头/脚/道具边缘
    // （96% 窗口曾被实测裁掉角色腿部约 10%）。
    // 只有当强主体占原始包围盒面积不足一半（存在明显长尾场景）时才收紧；
    // 若图片本身已紧贴主体（如整幅都是角色），直接保留原始包围盒，避免切头脚。
    let rawArea = (maxRow - minRow + 1) * (maxColumn - minColumn + 1)
    let subjectDensity = rawArea > 0 ? Double(strongTotal) / Double(rawArea) : 1
    if strongTotal > 0, subjectDensity < 0.5 {
      let rowWindow = Self.massWindow(
        strongRowDensity,
        total: strongTotal,
        low: 0.001,
        high: 0.999,
        fallbackMin: minRow,
        fallbackMax: maxRow
      )
      let columnWindow = Self.massWindow(
        strongColumnDensity,
        total: strongTotal,
        low: 0.001,
        high: 0.999,
        fallbackMin: minColumn,
        fallbackMax: maxColumn
      )
      minRow = rowWindow.min
      maxRow = rowWindow.max
      minColumn = columnWindow.min
      maxColumn = columnWindow.max
    }

    // 位图内存第 0 行即图像视觉顶部，与 CGImage.cropping 的 y=0 一致，直接使用行列。
    let cropRect = CGRect(
      x: minColumn,
      y: minRow,
      width: maxColumn - minColumn + 1,
      height: maxRow - minRow + 1
    )
    guard let cropped = processed.cropping(to: cropRect) else { return nil }

    let cellWidth = Int(SpriteSheetSpec.frameWidth)
    let cellHeight = Int(SpriteSheetSpec.frameHeight)
    let scale = min(
      SpriteSheetSpec.frameWidth / cropRect.width,
      SpriteSheetSpec.frameHeight / cropRect.height
    )
    let fittedWidth = cropRect.width * scale
    let fittedHeight = cropRect.height * scale
    guard
      let cellContext = CGContext(
        data: nil,
        width: cellWidth,
        height: cellHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { return nil }
    cellContext.clear(CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
    cellContext.interpolationQuality = .high
    cellContext.draw(
      cropped,
      in: CGRect(
        x: (SpriteSheetSpec.frameWidth - fittedWidth) / 2,
        y: (SpriteSheetSpec.frameHeight - fittedHeight) / 2,
        width: fittedWidth,
        height: fittedHeight
      )
    )
    return cellContext.makeImage()
  }

  /// 返回累计质量落在 [low, high] 区间的行/列索引窗口；统计异常时回退原始包围盒。
  private static func massWindow(
    _ counts: [Int],
    total: Int,
    low: Double,
    high: Double,
    fallbackMin: Int,
    fallbackMax: Int
  ) -> (min: Int, max: Int) {
    guard total > 0, low >= 0, high <= 1, low < high else {
      return (fallbackMin, fallbackMax)
    }
    var accumulated = 0
    var start: Int?
    var end = counts.count - 1
    for index in 0..<counts.count {
      accumulated += counts[index]
      if start == nil, Double(accumulated) >= Double(total) * low {
        start = index
      }
      if Double(accumulated) >= Double(total) * high {
        end = index
        break
      }
    }
    guard let start, start <= end else { return (fallbackMin, fallbackMax) }
    return (start, end)
  }

  /// 图片边缘是否自带透明背景：四条边缘平均 alpha 明显低于不透明则判定为透明底。
  private static func edgeIsTransparent(
    bytes: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> Bool {
    var total = 0
    var count = 0
    for column in 0..<width {
      total += Int(bytes[column * 4 + 3])
      total += Int(bytes[(height - 1) * bytesPerRow + column * 4 + 3])
      count += 2
    }
    for row in 0..<height {
      total += Int(bytes[row * bytesPerRow + 3])
      total += Int(bytes[row * bytesPerRow + (width - 1) * 4 + 3])
      count += 2
    }
    guard count > 0 else { return false }
    return total / count < 250
  }

  /// 从图像四条边缘做 4-连通 flood-fill，标记与边缘连通的背景像素。
  /// 候选判定：软抠 alpha < 0.9（含白色背景与主体内部同色像素——后者因被主体
  /// 包围而无法被 flood 到达，得以保留为不透明）。
  private static func floodBackground(
    alpha8: [UInt8],
    flood: inout [UInt8],
    width: Int,
    height: Int
  ) {
    let threshold: UInt8 = 230
    var stack: [Int] = []

    func push(_ index: Int) {
      guard flood[index] == 0, alpha8[index] < threshold else { return }
      flood[index] = 1
      stack.append(index)
    }

    for column in 0..<width {
      push(column)
      push((height - 1) * width + column)
    }
    for row in 0..<height {
      push(row * width)
      push(row * width + width - 1)
    }

    while let index = stack.popLast() {
      let row = index / width
      let column = index % width
      if row > 0 { push(index - width) }
      if row + 1 < height { push(index + width) }
      if column > 0 { push(index - 1) }
      if column + 1 < width { push(index + 1) }
    }
  }

  private static func averageBackgroundColor(
    bytes: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let corners = [
      (0, 0),
      (width - 1, 0),
      (0, height - 1),
      (width - 1, height - 1),
    ]
    var totalR = 0
    var totalG = 0
    var totalB = 0
    for (x, y) in corners {
      let offset = y * bytesPerRow + x * 4
      totalR += Int(bytes[offset])
      totalG += Int(bytes[offset + 1])
      totalB += Int(bytes[offset + 2])
    }
    return (
      r: CGFloat(totalR) / 255 / CGFloat(corners.count),
      g: CGFloat(totalG) / 255 / CGFloat(corners.count),
      b: CGFloat(totalB) / 255 / CGFloat(corners.count)
    )
  }
}
