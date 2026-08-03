import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// 帧动画头像视图：
/// - 有精灵图时按 `PetAnimState` 逐帧播放（restart / pingpong）
/// - 无精灵图时回退为静态头像 + 轻微呼吸浮动
struct AnimatedAvatarView: View {
  let image: NSImage?
  let spritesheet: CGImage?
  let animState: PetAnimState
  let displayMode: AvatarDisplayMode

  private var row: AnimationRow { animState.row }

  var body: some View {
    ZStack {
      if let spritesheet {
        let nsImage = NSImage(
          cgImage: frameImage(from: spritesheet),
          size: NSSize(
            width: SpriteSheetSpec.frameWidth,
            height: SpriteSheetSpec.frameHeight
          )
        )
        Image(nsImage: nsImage)
          .resizable()
          .scaledToFill()
      } else if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        placeholder
      }
    }
    .clipShape(
      displayMode == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20))
    )
    .overlay(
      (displayMode == .circle
        ? AnyShape(Circle())
        : AnyShape(RoundedRectangle(cornerRadius: 20))).stroke(.white, lineWidth: 5)
    )
    .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
  }

  private var placeholder: some View {
    ZStack {
      Circle().fill(Color(red: 0.96, green: 0.82, blue: 0.72))
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 76, weight: .regular))
        .foregroundStyle(.white.opacity(0.92))
    }
  }

  private func frameImage(from sheet: CGImage) -> CGImage {
    // 静态模式：直接显示当前状态行的基准帧，不做帧动画（先不启用微动作）。
    let rect = animState.frameRect(index: staticFrameIndex)
    // 精灵图规范与 CGImage.cropping 同为“y=0 在视觉顶部”，直接按行/列裁剪。
    // （实测：本 SDK 上 cropping 的 y=0 对应图像顶部；曾误做 y 翻转导致行映射上下颠倒。）
    let cropRect = CGRect(
      x: rect.minX,
      y: rect.minY,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
    return sheet.cropping(to: cropRect) ?? sheet
  }

  /// 静态模式下每个状态行显示的基准帧（避开眨眼/位移/旋转帧）。
  private var staticFrameIndex: Int {
    switch row {
    case .happy, .surprised: 1
    default: 0
    }
  }
}

private struct AnyShape: Shape {
  private let pathBuilder: @Sendable (CGRect) -> Path

  init<S: Shape>(_ shape: S) {
    pathBuilder = { rect in shape.path(in: rect) }
  }

  func path(in rect: CGRect) -> Path {
    pathBuilder(rect)
  }
}
