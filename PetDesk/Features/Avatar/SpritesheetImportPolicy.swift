import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 用户导入精灵图时的校验错误。
public enum SpritesheetImportError: Error, Sendable, Equatable {
  case unreadableImage
  case unsupportedType
  case invalidDimensions
  case missingAlpha
  case sparseCell(row: Int, column: Int)
}

/// 精灵图导入校验：格式、精确尺寸（1536×1664）、透明背景、已用帧内容非空。
/// 规则参考 hatch-pet validate_atlas.py（按本项目的 8 行规格裁剪）。
public struct SpritesheetImportPolicy: Sendable {
  public static let expectedWidth =
    Int(SpriteSheetSpec.frameWidth) * SpriteSheetSpec.columns
  public static let expectedHeight =
    Int(SpriteSheetSpec.frameHeight) * AnimationRow.allCases.count
  public let minUsedPixels: Int

  public init(minUsedPixels: Int = 50) {
    self.minUsedPixels = minUsedPixels
  }

  public func validate(url: URL) throws -> CGImage {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw SpritesheetImportError.unreadableImage
    }
    if let type = CGImageSourceGetType(source) {
      let identifier = type as String
      guard
        identifier == UTType.png.identifier || identifier == UTType.webP.identifier
      else {
        throw SpritesheetImportError.unsupportedType
      }
    }
    try validate(image: image)
    return image
  }

  public func validate(image: CGImage) throws {
    guard
      image.width == Self.expectedWidth && image.height == Self.expectedHeight
    else {
      throw SpritesheetImportError.invalidDimensions
    }
    let alpha = image.alphaInfo
    guard
      alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast
    else {
      throw SpritesheetImportError.missingAlpha
    }
    try validateUsedCellsHaveContent(in: image)
  }

  /// 每个动画行已用帧必须包含足够多的非透明像素（防止整行空白）。
  private func validateUsedCellsHaveContent(in image: CGImage) throws {
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
    else {
      throw SpritesheetImportError.unreadableImage
    }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    let bytes = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)
    for row in AnimationRow.allCases {
      for column in 0..<row.frameCount {
        var nontransparent = 0
        for y in (row.rawValue * frameH)..<((row.rawValue + 1) * frameH) {
          for x in (column * frameW)..<((column + 1) * frameW) {
            let offset = y * context.bytesPerRow + x * 4
            if bytes[offset + 3] > 8 {
              nontransparent += 1
            }
          }
          if nontransparent >= minUsedPixels { break }
        }
        guard nontransparent >= minUsedPixels else {
          throw SpritesheetImportError.sparseCell(row: row.rawValue, column: column)
        }
      }
    }
  }
}
