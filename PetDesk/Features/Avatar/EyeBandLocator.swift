import CoreGraphics
import Foundation
import Vision

/// 定位头像中眼睛区域的协议（返回源图像像素坐标，原点左下，与 Core Graphics 一致）。
public protocol EyeBandLocating {
  func eyeBand(in image: CGImage) -> CGRect?
}

/// 基于 Vision 人脸关键点定位眼睛的默认实现；检测失败返回 nil（调用方回退固定位置）。
public struct VisionEyeBandLocator: EyeBandLocating {
  public init() {}

  public func eyeBand(in image: CGImage) -> CGRect? {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    try? handler.perform([request])
    guard
      let face = request.results?.first,
      let landmarks = face.landmarks,
      let leftEye = landmarks.leftEye,
      let rightEye = landmarks.rightEye,
      !leftEye.normalizedPoints.isEmpty,
      !rightEye.normalizedPoints.isEmpty
    else { return nil }

    let leftMid = Self.midpoint(of: leftEye.normalizedPoints)
    let rightMid = Self.midpoint(of: rightEye.normalizedPoints)
    let eyeMidX = (leftMid.x + rightMid.x) / 2
    let eyeMidY = (leftMid.y + rightMid.y) / 2
    let eyeDistance = max(hypot(rightMid.x - leftMid.x, rightMid.y - leftMid.y), 0.02)

    // 以眼间距为基准推导遮罩宽高（归一化坐标），并夹到合理范围。
    let bandWidth = min(max(eyeDistance * 2.4, 0.20), 0.65)
    let bandHeight = min(max(eyeDistance * 0.35, 0.035), 0.14)
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let band = CGRect(
      x: (eyeMidX - bandWidth / 2) * width,
      y: (eyeMidY - bandHeight / 2) * height,
      width: bandWidth * width,
      height: bandHeight * height
    )
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let clamped = band.intersection(bounds)
    return clamped.width > 0 && clamped.height > 0 ? clamped : nil
  }

  private static func midpoint(of points: [CGPoint]) -> CGPoint {
    let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
  }
}
