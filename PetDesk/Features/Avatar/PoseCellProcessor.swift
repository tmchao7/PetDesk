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
