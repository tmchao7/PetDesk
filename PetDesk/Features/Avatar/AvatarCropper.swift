import CoreGraphics
import Foundation

public enum AvatarCropper {
  public static func crop(
    image: CGImage,
    viewSize: CGFloat,
    panOffset: CGSize,
    zoomScale: CGFloat,
    outputSize: Int
  ) -> CGImage? {
    let imageW = CGFloat(image.width)
    let imageH = CGFloat(image.height)
    guard imageW > 0, imageH > 0 else { return nil }

    let scale = max(viewSize / imageW, viewSize / imageH) * zoomScale
    let renderedW = imageW * scale
    let renderedH = imageH * scale

    let centerInRendered = CGPoint(
      x: renderedW / 2 - panOffset.width,
      y: renderedH / 2 - panOffset.height
    )

    let cropDiameterInRendered = viewSize
    let cropRadius = cropDiameterInRendered / 2

    let srcX = (centerInRendered.x - cropRadius) / scale
    let srcY = (centerInRendered.y - cropRadius) / scale
    let srcSize = cropDiameterInRendered / scale

    let safeX = max(srcX, 0)
    let safeY = max(srcY, 0)
    let safeW = min(srcSize, imageW - safeX)
    let safeH = min(srcSize, imageH - safeY)

    guard safeW > 0, safeH > 0 else { return nil }

    // 输出是方形：裁剪区必须保持方形，否则非方形区域会被拉伸变形。
    // 取 min 后围绕请求中心重新居中，并夹紧到图像边界。
    let side = min(safeW, safeH)
    let clampedX = min(max(safeX, 0), max(imageW - side, 0))
    let clampedY = min(max(safeY, 0), max(imageH - side, 0))

    let cropRect = CGRect(x: clampedX, y: clampedY, width: side, height: side)
    guard let cropped = image.cropping(to: cropRect) else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: outputSize,
        height: outputSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
    return context.makeImage()
  }
}
