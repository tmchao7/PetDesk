import SwiftUI

/// Shape 类型擦除包装（系统 AnyShape 到 macOS 14 才可用）。
/// 历史上在 PetView / AnimatedAvatarView / AvatarView / AvatarEditorView
/// 里各复制了一份，统一收口到 Shared 避免重复定义。
struct AnyShape: Shape {
  private let pathBuilder: @Sendable (CGRect) -> Path

  init<S: Shape>(_ shape: S) {
    pathBuilder = { rect in shape.path(in: rect) }
  }

  func path(in rect: CGRect) -> Path {
    pathBuilder(rect)
  }
}
