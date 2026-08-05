import AppKit
import CoreGraphics

/// 头像/姿势预览缩略图工厂：真正降采样绘制小位图，
/// 避免 `NSImage(cgImage:size:)` 只改显示尺寸却保留全分辨率数据的陷阱。
enum AvatarPreviewImageFactory {
  /// 生成指定尺寸的降采样预览；尺寸非法返回 nil，不记录源路径/文件名。
  static func makePreview(from image: CGImage, size: CGSize) -> NSImage? {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0 else { return nil }

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let preview = context.makeImage() else { return nil }
    return NSImage(
      cgImage: preview,
      size: NSSize(width: width, height: height)
    )
  }
}
