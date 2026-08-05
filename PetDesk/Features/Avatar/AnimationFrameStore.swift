import AppKit
import CoreGraphics

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// 动画帧预切片缓存：按（精灵图, 动作行, 帧数）一次性裁出全部帧，
/// 同时缓存成对的 `CGImage`（供 CALayer 播放）与 `NSImage`（供 SwiftUI 显示）。
/// 播放期间零 crop、零 NSImage 包装；精灵图更换或视图消失时调用 `clear()`。
@MainActor
final class AnimationFrameStore {
  /// 一次预切片的结果：CGImage 与 NSImage 一一对应。
  struct PreparedAnimationFrames {
    let cgImages: [CGImage]
    let nsImages: [NSImage]
    var count: Int { cgImages.count }
  }

  private struct CacheKey: Equatable {
    let sheetID: UInt
    let row: AnimationRow
    let frameCount: Int
  }

  private var cache: PreparedAnimationFrames?
  private var cacheKey: CacheKey?
  /// 强引用精灵图，保证地址在命中比较期间不被复用。
  private var retainedSheet: CGImage?

  /// 预切片指定行的帧。帧数非法（<=0）时返回单帧安全回退；
  /// 帧数超过可用列数时夹紧到列数。同 key 命中直接复用已准备帧。
  func preload(sheet: CGImage, row: AnimationRow, frameCount: Int) -> PreparedAnimationFrames {
    let clampedCount = max(1, min(frameCount, SpriteSheetSpec.columns))
    let sheetID = UInt(bitPattern: Unmanaged.passUnretained(sheet).toOpaque())
    let key = CacheKey(sheetID: sheetID, row: row, frameCount: clampedCount)

    if let cache, cacheKey == key {
      return cache
    }

    let frames = Self.slice(sheet: sheet, row: row, frameCount: clampedCount)
    let prepared = PreparedAnimationFrames(
      cgImages: frames,
      nsImages: frames.map { frame in
        NSImage(
          cgImage: frame,
          size: NSSize(width: SpriteSheetSpec.frameWidth, height: SpriteSheetSpec.frameHeight)
        )
      })
    cache = prepared
    cacheKey = key
    retainedSheet = sheet
    return prepared
  }

  /// 清空缓存（精灵图替换或视图消失时调用）。
  func clear() {
    cache = nil
    cacheKey = nil
    retainedSheet = nil
  }

  /// 按行/列裁出帧；裁切失败时回退到该行第一格。
  private static func slice(sheet: CGImage, row: AnimationRow, frameCount: Int) -> [CGImage] {
    let frameW = Int(SpriteSheetSpec.frameWidth)
    let frameH = Int(SpriteSheetSpec.frameHeight)
    let y = row.rawValue * frameH
    var frames: [CGImage] = []
    for col in 0..<frameCount {
      let rect = CGRect(x: col * frameW, y: y, width: frameW, height: frameH)
      frames.append(sheet.cropping(to: rect) ?? sheet)
    }
    return frames
  }
}
