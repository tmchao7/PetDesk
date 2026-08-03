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
    // 从四角采样实际背景色（色彩管理可能偏移 #FF00FF），再按该色做软抠图。
    let background = Self.averageBackgroundColor(
      bytes: bytes,
      width: width,
      height: height,
      bytesPerRow: context.bytesPerRow
    )
    let inner = chromaTolerance * 0.55
    let outer = chromaTolerance
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

        // 预乘 alpha：RGB 存 color*alpha；全透明像素清为 0，避免隐藏残留色。
        if alpha < 0.02 {
          bytes[offset] = 0
          bytes[offset + 1] = 0
          bytes[offset + 2] = 0
          bytes[offset + 3] = 0
        } else {
          bytes[offset] = UInt8((r * alpha * 255).rounded())
          bytes[offset + 1] = UInt8((g * alpha * 255).rounded())
          bytes[offset + 2] = UInt8((b * alpha * 255).rounded())
          bytes[offset + 3] = UInt8((alpha * 255).rounded())
          if alpha >= 0.5 {
            strongRowDensity[row] += 1
            strongColumnDensity[column] += 1
            strongTotal += 1
          }
          if bytes[offset + 3] > 8 {
            minColumn = min(minColumn, column)
            maxColumn = max(maxColumn, column)
            minRow = min(minRow, row)
            maxRow = max(maxRow, row)
          }
        }
      }
    }

    guard maxColumn >= minColumn, maxRow >= minRow, let processed = context.makeImage() else {
      return nil
    }

    // 保留包含中央 96% 强主体的行/列窗口（两侧各裁掉 2% 长尾）：
    // 场景边缘、桌面、阴影等占比低的区域被排除，角色在帧内更大、更居中。
    // 若统计异常则回退到原始包围盒，绝不裁成空。
    if strongTotal > 0 {
      let rowWindow = Self.massWindow(
        strongRowDensity,
        total: strongTotal,
        low: 0.02,
        high: 0.98,
        fallbackMin: minRow,
        fallbackMax: maxRow
      )
      let columnWindow = Self.massWindow(
        strongColumnDensity,
        total: strongTotal,
        low: 0.02,
        high: 0.98,
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
