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
/// 纯色背景自动抠底（边缘中位数采样）、裁剪到主体包围盒、contain-fit 居中。
/// 多帧组导入的跨帧归一化（统一缩放/锚点/背景）见 `PoseFrameSetProcessor`，
/// 两者共享本文件的位图级抠底管线。
public enum PoseCellProcessor {
  static let maxRGBDistance = sqrt(3.0)

  /// 从 PNG/WebP 文件读取姿势图并处理成动画单元。
  public static func loadCell(from url: URL) throws -> CGImage {
    let image = try loadImage(from: url)
    guard let cell = makeCell(from: image) else {
      throw PoseImageImportError.emptySubject
    }
    return cell
  }

  /// 从 PNG/WebP 文件读取姿势图原图（校验 UTType，不做处理）。
  /// 多帧导入先批量取原图，再交给 `PoseFrameSetProcessor` 统一处理。
  public static func loadImage(from url: URL) throws -> CGImage {
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
    return image
  }

  /// - Parameter chromaTolerance: 归一化背景距离阈值（0-1），0.18 对应 ImageMagick
  ///   `-fuzz 18%`；阈值内做软抠图避免抗锯齿边缘。
  public static func makeCell(from image: CGImage, chromaTolerance: CGFloat = 0.18) -> CGImage? {
    guard let bitmap = prepareFrame(image) else { return nil }
    let hasTransparentBackground = bitmap.hasTransparentBackground
    let background =
      hasTransparentBackground
      ? (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
      : edgeMedianBackground(bitmap)
    guard
      let keyed = keyFrame(
        bitmap, background: background, chromaTolerance: chromaTolerance)
    else { return nil }

    // 保留包含中央 99.8% 强主体的行/列窗口（两侧各裁掉 0.1% 长尾）：
    // 只剔除极端稀疏的边缘杂色；窗口过窄会切到角色的头/脚/道具边缘
    // （96% 窗口曾被实测裁掉角色腿部约 10%）。
    // 只有当强主体占原始包围盒面积不足一半（存在明显长尾场景）时才收紧；
    // 若图片本身已紧贴主体（如整幅都是角色），直接保留原始包围盒，避免切头脚。
    var minRow = keyed.minRow
    var maxRow = keyed.maxRow
    var minColumn = keyed.minColumn
    var maxColumn = keyed.maxColumn
    let rawArea = (maxRow - minRow + 1) * (maxColumn - minColumn + 1)
    let subjectDensity = rawArea > 0 ? Double(keyed.strongTotal) / Double(rawArea) : 1
    if keyed.strongTotal > 0, subjectDensity < 0.5 {
      let rowWindow = massWindow(
        keyed.strongRowDensity,
        total: keyed.strongTotal,
        low: 0.001,
        high: 0.999,
        fallbackMin: minRow,
        fallbackMax: maxRow
      )
      let columnWindow = massWindow(
        keyed.strongColumnDensity,
        total: keyed.strongTotal,
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
    guard let processed = keyed.context.makeImage(),
      let cropped = processed.cropping(to: cropRect)
    else { return nil }

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
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
        ).rawValue
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
    guard let cell = cellContext.makeImage() else { return nil }
    // 最终单元：去背景色残留（defringe）+ 边缘羽化。抠底路径带 chroma 参考色
    // 做 defringe；自带透明背景路径无参考色，仅羽化。
    return defringeAndFeather(
      cell,
      chromaBackground: hasTransparentBackground ? nil : background
    )
  }

  // MARK: - 位图级抠底管线（单帧 makeCell 与多帧 PoseFrameSetProcessor 共用）

  /// 已解码进位图上下文的姿势帧（抠底前的预备态）。
  struct PoseFrameBitmap {
    let context: CGContext
    let bytes: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
    /// 图片本身带透明背景（边缘有明显透明像素）——直接使用原 alpha，不做抠底。
    let hasTransparentBackground: Bool
  }

  /// 抠底完成的姿势帧：位图字节已写回（背景清零/主体保留）+ 主体统计。
  /// bbox / 密度 / 质心均为整幅源图坐标（视觉 y 向下）。
  struct KeyedPoseFrame {
    let context: CGContext
    let width: Int
    let height: Int
    let minColumn: Int
    let maxColumn: Int
    let minRow: Int
    let maxRow: Int
    let strongTotal: Int
    let strongRowDensity: [Int]
    let strongColumnDensity: [Int]
    /// 强主体（alpha ≥ 128）像素质心。
    let strongCentroid: (x: Double, y: Double)
  }

  /// 把 CGImage 解码进 DeviceRGB premultipliedLast 位图上下文并判断是否自带透明背景。
  static func prepareFrame(_ image: CGImage) -> PoseFrameBitmap? {
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
    let hasTransparentBackground = edgeIsTransparent(
      bytes: bytes,
      width: width,
      height: height,
      bytesPerRow: context.bytesPerRow
    )
    return PoseFrameBitmap(
      context: context,
      bytes: bytes,
      width: width,
      height: height,
      bytesPerRow: context.bytesPerRow,
      hasTransparentBackground: hasTransparentBackground
    )
  }

  /// 背景色估计：四条边缘采样像素的逐通道中位数。
  /// AI 生成图的四角颜色常不一致（白 + 暖色桌面），四角平均会偏色；
  /// 边缘中位数对混合角落与局部杂物稳健。
  static func edgeMedianBackground(_ bitmap: PoseFrameBitmap) -> (
    r: CGFloat, g: CGFloat, b: CGFloat
  ) {
    let width = bitmap.width
    let height = bitmap.height
    let stride = max(1, min(width, height) / 256)
    var reds: [Int] = []
    var greens: [Int] = []
    var blues: [Int] = []
    func sample(_ x: Int, _ y: Int) {
      let offset = y * bitmap.bytesPerRow + x * 4
      reds.append(Int(bitmap.bytes[offset]))
      greens.append(Int(bitmap.bytes[offset + 1]))
      blues.append(Int(bitmap.bytes[offset + 2]))
    }
    for column in Swift.stride(from: 0, to: width, by: stride) {
      sample(column, 0)
      sample(column, height - 1)
    }
    for row in Swift.stride(from: 0, to: height, by: stride) {
      sample(0, row)
      sample(width - 1, row)
    }
    func median(_ values: [Int]) -> CGFloat {
      guard !values.isEmpty else { return 0 }
      let sorted = values.sorted()
      return CGFloat(sorted[sorted.count / 2])
    }
    return (
      r: median(reds) / 255,
      g: median(greens) / 255,
      b: median(blues) / 255
    )
  }

  /// 对预备帧执行软抠图 + 边缘 flood + 泄漏救回 + 软带保留，写回位图字节并统计主体。
  /// - Returns: 主体为空（无 alpha > 8 像素）时返回 nil。
  static func keyFrame(
    _ bitmap: PoseFrameBitmap,
    background: (r: CGFloat, g: CGFloat, b: CGFloat),
    chromaTolerance: CGFloat
  ) -> KeyedPoseFrame? {
    let width = bitmap.width
    let height = bitmap.height
    let bytes = bitmap.bytes
    let bytesPerRow = bitmap.bytesPerRow
    let hasTransparentBackground = bitmap.hasTransparentBackground
    let inner = chromaTolerance * 0.55
    let outer = chromaTolerance

    // 每个像素的软抠 alpha（0-255）。先不动原始字节，稍后按 flood 结果统一输出。
    var alpha8 = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        let offset = row * bytesPerRow + column * 4
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

    // 边缘 flood-fill 抠底：只清除与图像边缘连通的、颜色近似背景的像素
    // （硬带 a < 8，即距离 ≤ inner）。软带像素（inner < 距离 ≤ outer）
    // 不参与 flood——它们可能是主体自身的浅色细节（与背景同色系），
    // 交给下方的泄漏救回 / 软带组件规则区分；只有几乎等于背景色的像素
    // 才被移除，避免“白色部分变透明”（参考 pixa/transparent.rs 与
    // R2beat 精灵图脚本的边缘连通策略 + 泄漏救回）。
    var flood = [UInt8](repeating: 0, count: width * height)
    // 泄漏救回 / 软带细节保留掩码（仅抠底路径需要；自带透明背景时原样用 alpha）。
    var rescued: [Bool] = []
    var keptSoft: [Bool] = []
    if !hasTransparentBackground {
      floodBackground(alpha8: alpha8, flood: &flood, width: width, height: height)
      rescued = rescueFloodedInteriors(flood: flood, width: width, height: height)
      keptSoft = keptSoftComponents(alpha8: alpha8, flood: flood, width: width, height: height)
    }

    // 统一输出 + 统计最终 bbox / 强主体密度 / 强主体质心。
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
    var strongSumX = 0
    var strongSumY = 0

    for row in 0..<height {
      for column in 0..<width {
        let offset = row * bytesPerRow + column * 4
        let index = row * width + column
        let a = alpha8[index]
        if flood[index] == 1 && !rescued[index] {
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
        } else if rescued[index] || a < 8 || keptSoft[index] {
          // 主体：被救回的内部背景色（白色肚皮/脸等）、或与背景同色系的
          // 浅色主体细节——恢复为不透明，保留原始颜色。
          bytes[offset + 3] = 255
        } else if a < 230 {
          // 细窄软带（抗锯齿边缘 / 泄漏通道残余）：清除。
          bytes[offset] = 0
          bytes[offset + 1] = 0
          bytes[offset + 2] = 0
          bytes[offset + 3] = 0
        } else {
          // 强主体：预乘比例 ≈ 1，原样保留。
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
          strongSumX += column
          strongSumY += row
        }
      }
    }

    guard maxColumn >= minColumn, maxRow >= minRow else { return nil }
    // 无强主体像素（整幅只有半透明软带）时用包围盒中心充当质心。
    let centroidX =
      strongTotal > 0
      ? Double(strongSumX) / Double(strongTotal)
      : Double(minColumn + maxColumn) / 2
    let centroidY =
      strongTotal > 0
      ? Double(strongSumY) / Double(strongTotal)
      : Double(minRow + maxRow) / 2
    return KeyedPoseFrame(
      context: bitmap.context,
      width: width,
      height: height,
      minColumn: minColumn,
      maxColumn: maxColumn,
      minRow: minRow,
      maxRow: maxRow,
      strongTotal: strongTotal,
      strongRowDensity: strongRowDensity,
      strongColumnDensity: strongColumnDensity,
      strongCentroid: (x: centroidX, y: centroidY)
    )
  }

  /// 对最终 192×208 单元做边缘融合：
  /// - defringe：轮廓外沿与背景同色的残留像素（抠底过渡带被保留的浅色环）的
  ///   RGB 级联替换为内侧本体色，消除深色桌面上的“分割线/边框”感；
  /// - 羽化：最外 1~2px alpha 线性衰减，轮廓柔和融入桌面。
  /// 只作用于最终单元，不影响 bbox / 强主体密度统计（那些在裁剪前已算完）。
  static func defringeAndFeather(
    _ cell: CGImage,
    chromaBackground: (r: CGFloat, g: CGFloat, b: CGFloat)?,
    featherRadius: Int = 2,
    featherOuterAlpha: Int = 140,
    defringeDepth: Int = 6,
    defringeGate: CGFloat = 0.18
  ) -> CGImage? {
    let width = cell.width
    let height = cell.height
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
    context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)

    var alpha = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
      for column in 0..<width {
        alpha[row * width + column] = bytes[row * context.bytesPerRow + column * 4 + 3]
      }
    }
    let dist = edgeDistance(alpha: alpha, width: width, height: height)

    if let chromaBackground {
      defringeColors(
        bytes: bytes,
        bytesPerRow: context.bytesPerRow,
        dist: dist,
        width: width,
        height: height,
        chromaBackground: chromaBackground,
        depth: defringeDepth,
        gate: defringeGate
      )
    }
    featherEdges(
      bytes: bytes,
      bytesPerRow: context.bytesPerRow,
      dist: dist,
      width: width,
      height: height,
      radius: featherRadius,
      outerAlpha: featherOuterAlpha
    )
    return context.makeImage()
  }

  /// 到最近透明像素的 8-连通（Chebyshev）步数距离场；透明像素 = 0。
  /// 8-连通使 45° 斜边与轴向的羽化带宽度一致，不畸变。
  private static func edgeDistance(alpha: [UInt8], width: Int, height: Int) -> [Int] {
    var dist = [Int](repeating: 0, count: width * height)
    var visited = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    for index in 0..<(width * height) where alpha[index] < 8 {
      visited[index] = true
      queue.append(index)
    }
    let neighbors = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    var head = 0
    while head < queue.count {
      let index = queue[head]
      head += 1
      let row = index / width
      let column = index % width
      for (dr, dc) in neighbors {
        let nr = row + dr
        let nc = column + dc
        guard nr >= 0, nr < height, nc >= 0, nc < width else { continue }
        let n = nr * width + nc
        guard !visited[n], alpha[n] >= 8 else { continue }
        visited[n] = true
        dist[n] = dist[index] + 1
        queue.append(n)
      }
    }
    return dist
  }

  /// Defringe：把轮廓外沿“颜色接近背景色”的不透明像素，级联（内→外）替换为
  /// 内侧本体色。门控优先于深度——角色自身深色描边即使在外沿也不被碰；
  /// 级联让颜色从内到外平滑传播，不会出现一圈突兀的均一色带。
  /// 只改 RGB 不改 alpha（羽化阶段统一处理）。
  private static func defringeColors(
    bytes: UnsafeMutablePointer<UInt8>,
    bytesPerRow: Int,
    dist: [Int],
    width: Int,
    height: Int,
    chromaBackground: (r: CGFloat, g: CGFloat, b: CGFloat),
    depth: Int,
    gate: CGFloat
  ) {
    let neighbors = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    for ringDepth in stride(from: depth, through: 1, by: -1) {
      for row in 0..<height {
        for column in 0..<width {
          let index = row * width + column
          guard dist[index] == ringDepth else { continue }
          let offset = row * bytesPerRow + column * 4
          guard bytes[offset + 3] >= 230 else { continue }
          // 门控：颜色接近背景色 → 残留，替换为内侧色。
          let dr = CGFloat(bytes[offset]) / 255 - chromaBackground.r
          let dg = CGFloat(bytes[offset + 1]) / 255 - chromaBackground.g
          let db = CGFloat(bytes[offset + 2]) / 255 - chromaBackground.b
          let colorDistance = sqrt(dr * dr + dg * dg + db * db) / maxRGBDistance
          guard colorDistance < gate else { continue }
          // 内侧邻居平均色（alpha ≥ 200 的预乘像素 RGB 才接近直通色）。
          var sumR = 0
          var sumG = 0
          var sumB = 0
          var count = 0
          for (nrow, ncol) in neighbors {
            let nr = row + nrow
            let nc = column + ncol
            guard nr >= 0, nr < height, nc >= 0, nc < width else { continue }
            let n = nr * width + nc
            let noffset = nr * bytesPerRow + nc * 4
            guard dist[n] > ringDepth, bytes[noffset + 3] >= 200 else { continue }
            sumR += Int(bytes[noffset])
            sumG += Int(bytes[noffset + 1])
            sumB += Int(bytes[noffset + 2])
            count += 1
          }
          guard count > 0 else { continue }  // 细窄特征（触须/天线）无内侧邻居 → 保留原色
          bytes[offset] = UInt8((Double(sumR) / Double(count)).rounded())
          bytes[offset + 1] = UInt8((Double(sumG) / Double(count)).rounded())
          bytes[offset + 2] = UInt8((Double(sumB) / Double(count)).rounded())
        }
      }
    }
  }

  /// 羽化：最外 radius 层 alpha 线性衰减（d=1 → outerAlpha，向内递增到 255）。
  /// 缓冲是 premultipliedLast，改 alpha 必须同步预乘缩放 RGB，否则半透明边缘
  /// 会被压黑（经典 premultiplied 陷阱）。
  private static func featherEdges(
    bytes: UnsafeMutablePointer<UInt8>,
    bytesPerRow: Int,
    dist: [Int],
    width: Int,
    height: Int,
    radius: Int,
    outerAlpha: Int
  ) {
    for row in 0..<height {
      for column in 0..<width {
        let d = dist[row * width + column]
        guard d >= 1, d <= radius else { continue }
        let ramp = 255 - (255 - outerAlpha) * (radius + 1 - d) / radius
        let offset = row * bytesPerRow + column * 4
        let current = Int(bytes[offset + 3])
        let target = min(current, ramp)
        guard target < current else { continue }
        let scale = CGFloat(target) / CGFloat(current)
        bytes[offset] = UInt8((CGFloat(bytes[offset]) * scale).rounded())
        bytes[offset + 1] = UInt8((CGFloat(bytes[offset + 1]) * scale).rounded())
        bytes[offset + 2] = UInt8((CGFloat(bytes[offset + 2]) * scale).rounded())
        bytes[offset + 3] = UInt8(target)
      }
    }
  }

  /// 返回累计质量落在 [low, high] 区间的行/列索引窗口；统计异常时回退原始包围盒。
  static func massWindow(
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
  /// 候选判定：硬带软抠 alpha < 8（颜色距离 ≤ inner 的近似背景色）。
  /// 软带像素（inner < 距离 ≤ outer）不参与 flood——它们可能是主体自身的
  /// 浅色细节（与背景同色系，如白色肚皮/受光面），由泄漏救回与软带组件
  /// 规则区分；只清除几乎等于背景色的像素，避免“白色部分变透明”。
  private static func floodBackground(
    alpha8: [UInt8],
    flood: inout [UInt8],
    width: Int,
    height: Int
  ) {
    let threshold: UInt8 = 8
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

  /// 救回经“泄漏通道”（轮廓缺口、浅色道具接触等窄缝）被 flood 进入、但整体
  /// 仍被主体包围的内部背景色区域（如哆啦A梦的白色肚皮/脸）。
  /// 策略：把 flood 腐蚀 2 次，取与图像边缘断开的腐蚀区域为种子——真正的
  /// 背景是边缘连通的，腐蚀后仍连通；泄漏通道 ≤2px 宽，腐蚀 2 次后消失。
  /// 再在腐蚀 1 次后的 flood 内扩张（覆盖救回区域的 1px 过渡带）：通道已
  /// 消失，扩张无法经通道逃回背景，也不会救回腿间空隙等开放区域。
  private static func rescueFloodedInteriors(
    flood: [UInt8],
    width: Int,
    height: Int
  ) -> [Bool] {
    let eroded1 = erode(flood, times: 1, width: width, height: height)
    let eroded2 = erode(flood, times: 2, width: width, height: height)
    // 种子：与图像边缘断开的 eroded2 区域。
    var seeds = [Bool](repeating: false, count: width * height)
    var seen = [Bool](repeating: false, count: width * height)
    var stack: [Int] = []

    func markEdge(_ index: Int) {
      guard eroded2[index] == 1, !seen[index] else { return }
      seen[index] = true
      stack.append(index)
    }
    for column in 0..<width {
      markEdge(column)
      markEdge((height - 1) * width + column)
    }
    for row in 0..<height {
      markEdge(row * width)
      markEdge(row * width + width - 1)
    }
    while let index = stack.popLast() {
      let row = index / width
      let column = index % width
      if row > 0 { markEdge(index - width) }
      if row + 1 < height { markEdge(index + width) }
      if column > 0 { markEdge(index - 1) }
      if column + 1 < width { markEdge(index + 1) }
    }
    for index in 0..<(width * height) where eroded2[index] == 1 && !seen[index] {
      seeds[index] = true
    }

    // 种子周围 1 层 eroded1 邻居：只救回种子及其紧邻过渡带，不 BFS 蔓延。
    // 蔓延的陷阱：种子若与背景之间只隔着 1px 宽的 flood 通道（腐蚀 2 次
    // 后断开、腐蚀 1 次后仍连通，如 AI 图的角落浅灰渐变带），BFS 会经通道
    // 逃逸并把整个背景救回（实测摸鱼帧图 rescued 272 万像素 → cell 全白）。
    var rescued = seeds
    for index in 0..<(width * height) where rescued[index] {
      let row = index / width
      let column = index % width
      if row > 0 {
        let neighbor = index - width
        if eroded1[neighbor] == 1 { rescued[neighbor] = true }
      }
      if row + 1 < height {
        let neighbor = index + width
        if eroded1[neighbor] == 1 { rescued[neighbor] = true }
      }
      if column > 0 {
        let neighbor = index - 1
        if eroded1[neighbor] == 1 { rescued[neighbor] = true }
      }
      if column + 1 < width {
        let neighbor = index + 1
        if eroded1[neighbor] == 1 { rescued[neighbor] = true }
      }
    }
    return rescued
  }

  /// 形态学腐蚀：仅当 4-邻域全部在掩码内时保留该像素；图像边界像素缺少
  /// 邻域视为通过（边界仍保持与边缘连通，全背景图才不会误判为内部种子）。
  /// 迭代 times 次。
  private static func erode(_ mask: [UInt8], times: Int, width: Int, height: Int) -> [UInt8] {
    var current = mask
    for _ in 0..<times {
      var next = [UInt8](repeating: 0, count: width * height)
      for index in 0..<current.count where current[index] == 1 {
        let row = index / width
        let column = index % width
        let up = row == 0 || current[index - width] == 1
        let down = row + 1 == height || current[index + width] == 1
        let left = column == 0 || current[index - 1] == 1
        let right = column + 1 == width || current[index + 1] == 1
        if up && down && left && right { next[index] = 1 }
      }
      current = next
    }
    return current
  }

  /// 软带主体细节保留：非 flood 的软带像素（inner < 距离 ≤ outer）按 4-连通
  /// 分组；组件最小跨度 ≥ 4px 的是主体细节（浅色肚皮、受光面、内部阴影），
  /// 保留为不透明；细窄组件是抗锯齿边缘 / 泄漏通道残余，清除。
  /// 典型源图分辨率（≥256px）下抗锯齿带仅 1~3px 宽，4px 跨度足以区分。
  private static func keptSoftComponents(
    alpha8: [UInt8],
    flood: [UInt8],
    width: Int,
    height: Int
  ) -> [Bool] {
    var kept = [Bool](repeating: false, count: width * height)
    var seen = [Bool](repeating: false, count: width * height)
    for start in 0..<(width * height) {
      let alpha = alpha8[start]
      guard flood[start] == 0, alpha >= 8, alpha < 230, !seen[start] else { continue }
      var component: [Int] = []
      var stack: [Int] = [start]
      seen[start] = true
      var minRow = height
      var maxRow = 0
      var minColumn = width
      var maxColumn = 0

      func pushNeighbor(_ index: Int) {
        guard flood[index] == 0, !seen[index] else { return }
        let neighborAlpha = alpha8[index]
        guard neighborAlpha >= 8, neighborAlpha < 230 else { return }
        seen[index] = true
        stack.append(index)
      }
      while let index = stack.popLast() {
        component.append(index)
        let row = index / width
        let column = index % width
        minRow = min(minRow, row)
        maxRow = max(maxRow, row)
        minColumn = min(minColumn, column)
        maxColumn = max(maxColumn, column)
        if row > 0 { pushNeighbor(index - width) }
        if row + 1 < height { pushNeighbor(index + width) }
        if column > 0 { pushNeighbor(index - 1) }
        if column + 1 < width { pushNeighbor(index + 1) }
      }

      let span = min(maxColumn - minColumn + 1, maxRow - minRow + 1)
      if span >= 4 {
        for index in component { kept[index] = true }
      }
    }
    return kept
  }
}
