import CoreGraphics
import Foundation

public enum ScreenPositionResolver {
  public static func clamped(frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
    guard let visibleFrame = preferredVisibleFrame(for: frame, candidates: visibleFrames) else {
      return frame
    }
    let x = clampedOrigin(
      frameMin: frame.minX,
      frameLength: frame.width,
      visibleMin: visibleFrame.minX,
      visibleLength: visibleFrame.width
    )
    let y = clampedOrigin(
      frameMin: frame.minY,
      frameLength: frame.height,
      visibleMin: visibleFrame.minY,
      visibleLength: visibleFrame.height
    )
    return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
  }

  private static func preferredVisibleFrame(for frame: CGRect, candidates: [CGRect]) -> CGRect? {
    candidates.max { left, right in
      let leftIntersection = left.intersection(frame)
      let rightIntersection = right.intersection(frame)
      let leftArea = leftIntersection.isNull ? 0 : leftIntersection.width * leftIntersection.height
      let rightArea =
        rightIntersection.isNull ? 0 : rightIntersection.width * rightIntersection.height
      if leftArea != rightArea { return leftArea < rightArea }
      return squaredDistance(from: frame.center, to: left.center)
        > squaredDistance(from: frame.center, to: right.center)
    }
  }

  private static func clampedOrigin(
    frameMin: CGFloat,
    frameLength: CGFloat,
    visibleMin: CGFloat,
    visibleLength: CGFloat
  ) -> CGFloat {
    guard frameLength <= visibleLength else { return visibleMin }
    return min(max(frameMin, visibleMin), visibleMin + visibleLength - frameLength)
  }

  private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
    let x = lhs.x - rhs.x
    let y = lhs.y - rhs.y
    return x * x + y * y
  }
}

extension CGRect {
  fileprivate var center: CGPoint { CGPoint(x: midX, y: midY) }
}
