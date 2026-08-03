import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 用户导入精灵图时的校验/规整错误。
public enum SpritesheetImportError: Error, Sendable, Equatable {
  case unreadableImage
  case unsupportedType
  case invalidDimensions
  case invalidGrid
  case missingAlpha
  case sparseCell(row: Int, column: Int)
}

/// 精灵图导入校验与规整：
/// - 已是 1536×1664 且带透明通道 → 直接使用；
/// - 其余图若宽高都能被 8 整除，按 8×8 网格处理：纯色背景（四角同色）自动抠底，
///   网格线干净则逐格 contain-fit 重排成标准 1536×1664；
/// - 网格不整齐或背景不可抠 → 明确报错，避免静默导入错误布局。
/// 规则参考 hatch-pet validate_atlas.py（按本项目的 8 行规格裁剪）。
public struct SpritesheetImportPolicy: Sendable {
  public static let expectedWidth =
    Int(SpriteSheetSpec.frameWidth) * SpriteSheetSpec.columns
  public static let expectedHeight =
    Int(SpriteSheetSpec.frameHeight) * AnimationRow.allCases.count
  public let minUsedPixels: Int
  public let chromaTolerance: CGFloat

  public init(minUsedPixels: Int = 50, chromaTolerance: CGFloat = 0.18) {
    self.minUsedPixels = minUsedPixels
    self.chromaTolerance = chromaTolerance
  }

  /// 读取、规整并校验，返回可直接保存的标准精灵图。
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
    let prepared = try prepare(image: image)
    try validate(image: prepared)
    return prepared
  }

  /// 对已规整的标准精灵图做最终校验（尺寸、透明、已用帧内容）。
  public func validate(image: CGImage) throws {
    guard
      image.width == Self.expectedWidth && image.height == Self.expectedHeight
    else {
      throw SpritesheetImportError.invalidDimensions
    }
    guard Self.hasAlpha(image) else {
      throw SpritesheetImportError.missingAlpha
    }
    try validateUsedCellsHaveContent(in: image)
  }

  /// 规整任意 8×8 网格（或直接通过标准图）为标准精灵图。
  public func prepare(image: CGImage) throws -> CGImage {
    if image.width == Self.expectedWidth, image.height == Self.expectedHeight,
      Self.hasAlpha(image)
    {
      return image
    }
    guard image.width % 8 == 0, image.height % 8 == 0 else {
      throw SpritesheetImportError.invalidDimensions
    }
    let cellWidth = image.width / 8
    let cellHeight = image.height / 8
    guard cellWidth >= 64, cellHeight >= 64 else {
      throw SpritesheetImportError.invalidDimensions
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      ),
      let data = context.data
    else {
      throw SpritesheetImportError.unreadableImage
    }
    context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = data.bindMemory(to: UInt8.self, capacity: image.height * context.bytesPerRow)

    guard
      let background = Self.uniformBackgroundColor(
        bytes: bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: context.bytesPerRow
      )
    else {
      throw SpritesheetImportError.missingAlpha
    }
    Self.keyBackground(
      bytes: bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: context.bytesPerRow,
      background: background,
      tolerance: chromaTolerance
    )
    guard
      Self.gridLinesAreClean(
        bytes: bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: context.bytesPerRow,
        cellWidth: cellWidth,
        cellHeight: cellHeight
      )
    else {
      throw SpritesheetImportError.invalidGrid
    }
    guard let keyed = context.makeImage() else {
      throw SpritesheetImportError.unreadableImage
    }
    guard
      let sheet = Self.composeStandardSheet(
        from: keyed, cellWidth: cellWidth, cellHeight: cellHeight)
    else {
      throw SpritesheetImportError.unreadableImage
    }
    return sheet
  }

  private static func hasAlpha(_ image: CGImage) -> Bool {
    let alpha = image.alphaInfo
    return alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast
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

  // MARK: - Grid normalization

  /// 四角小块背景色一致则返回平均色（用于自动抠底），否则 nil。
  private static func uniformBackgroundColor(
    bytes: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
    let patch = 12
    let corners: [(x: Int, y: Int)] = [
      (0, 0),
      (width - patch, 0),
      (0, height - patch),
      (width - patch, height - patch),
    ]
    var samples: [(r: CGFloat, g: CGFloat, b: CGFloat)] = []
    for corner in corners {
      var r = 0
      var g = 0
      var b = 0
      var count = 0
      for y in corner.y..<(corner.y + patch) {
        for x in corner.x..<(corner.x + patch) {
          let offset = y * bytesPerRow + x * 4
          r += Int(bytes[offset])
          g += Int(bytes[offset + 1])
          b += Int(bytes[offset + 2])
          count += 1
        }
      }
      samples.append(
        (
          r: CGFloat(r) / 255 / CGFloat(count), g: CGFloat(g) / 255 / CGFloat(count),
          b: CGFloat(b) / 255 / CGFloat(count)
        ))
    }
    let mean = (
      r: samples.map(\.r).reduce(0, +) / CGFloat(samples.count),
      g: samples.map(\.g).reduce(0, +) / CGFloat(samples.count),
      b: samples.map(\.b).reduce(0, +) / CGFloat(samples.count)
    )
    let maxDistance =
      samples.map { sample -> CGFloat in
        let dr = sample.r - mean.r
        let dg = sample.g - mean.g
        let db = sample.b - mean.b
        return (dr * dr + dg * dg + db * db).squareRoot()
      }.max() ?? 1
    return maxDistance < 0.08 ? mean : nil
  }

  /// 以背景色做软抠图（预乘 alpha，透明像素 RGB 清零）。
  private static func keyBackground(
    bytes: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    background: (r: CGFloat, g: CGFloat, b: CGFloat),
    tolerance: CGFloat
  ) {
    let maxDistance = sqrt(3.0)
    let inner = tolerance * 0.55
    let outer = tolerance
    for row in 0..<height {
      for column in 0..<width {
        let offset = row * bytesPerRow + column * 4
        let r = CGFloat(bytes[offset]) / 255
        let g = CGFloat(bytes[offset + 1]) / 255
        let b = CGFloat(bytes[offset + 2]) / 255
        let dr = r - background.r
        let dg = g - background.g
        let db = b - background.b
        let distance = (dr * dr + dg * dg + db * db).squareRoot() / maxDistance
        let alpha: CGFloat
        if distance <= inner {
          alpha = 0
        } else if distance >= outer {
          alpha = 1
        } else {
          alpha = (distance - inner) / (outer - inner)
        }
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
        }
      }
    }
  }

  /// 8×8 网格线（第 1..7 条行/列边界）必须基本透明，否则视为角色跨格的不整齐布局。
  private static func gridLinesAreClean(
    bytes: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    cellWidth: Int,
    cellHeight: Int
  ) -> Bool {
    let strip = 4
    let maxContentFraction = 0.10
    for k in 1..<8 {
      var content = 0
      var total = 0
      let xStart = k * cellWidth - strip / 2
      for y in 0..<height {
        for x in xStart..<(xStart + strip) {
          guard x >= 0, x < width else { continue }
          let offset = y * bytesPerRow + x * 4
          if bytes[offset + 3] > 8 { content += 1 }
          total += 1
        }
      }
      if total > 0, CGFloat(content) / CGFloat(total) > maxContentFraction { return false }

      content = 0
      total = 0
      let yStart = k * cellHeight - strip / 2
      for y in yStart..<(yStart + strip) {
        guard y >= 0, y < height else { continue }
        for x in 0..<width {
          let offset = y * bytesPerRow + x * 4
          if bytes[offset + 3] > 8 { content += 1 }
          total += 1
        }
      }
      if total > 0, CGFloat(content) / CGFloat(total) > maxContentFraction { return false }
    }
    return true
  }

  /// 把抠底后的 8×8 网格逐格 contain-fit 重排为标准 1536×1664 精灵图。
  private static func composeStandardSheet(
    from keyed: CGImage,
    cellWidth: Int,
    cellHeight: Int
  ) -> CGImage? {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    let sheetWidth = frameW * SpriteSheetSpec.columns
    let sheetHeight = frameH * AnimationRow.allCases.count
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: sheetWidth,
        height: sheetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
    context.interpolationQuality = .high
    let scale = min(
      SpriteSheetSpec.frameWidth / CGFloat(cellWidth),
      SpriteSheetSpec.frameHeight / CGFloat(cellHeight)
    )
    let fittedWidth = CGFloat(cellWidth) * scale
    let fittedHeight = CGFloat(cellHeight) * scale
    let paddingX = (SpriteSheetSpec.frameWidth - fittedWidth) / 2
    let paddingY = (SpriteSheetSpec.frameHeight - fittedHeight) / 2
    for row in 0..<8 {
      for column in 0..<8 {
        let cellRect = CGRect(
          x: column * cellWidth,
          y: row * cellHeight,
          width: cellWidth,
          height: cellHeight
        )
        guard let cell = keyed.cropping(to: cellRect) else { continue }
        // CG 坐标 y 向上：视觉第 row 行放在顶部。
        let originY = CGFloat((7 - row) * frameH) + paddingY
        context.draw(
          cell,
          in: CGRect(
            x: CGFloat(column * frameW) + paddingX,
            y: originY,
            width: fittedWidth,
            height: fittedHeight
          )
        )
      }
    }
    return context.makeImage()
  }
}
