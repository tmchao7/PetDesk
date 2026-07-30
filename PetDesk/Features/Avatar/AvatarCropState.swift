import CoreGraphics
import Foundation

public enum AvatarDisplayMode: String, Sendable, Equatable, Codable {
  case circle
  case original
}

public struct AvatarCropState: Sendable, Equatable {
  public var panOffset: CGSize
  public var zoomScale: CGFloat
  public var displayMode: AvatarDisplayMode

  public init(
    panOffset: CGSize = .zero,
    zoomScale: CGFloat = 1.0,
    displayMode: AvatarDisplayMode = .circle
  ) {
    self.panOffset = panOffset
    self.zoomScale = zoomScale
    self.displayMode = displayMode
  }

  public static let `default` = AvatarCropState()
}
