import Foundation

/// 头像显示模式：圆形裁切或原图。
public enum AvatarDisplayMode: String, Sendable, Equatable, Codable {
  case circle
  case original
}
