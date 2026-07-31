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

  @State private var frameIndex = 0
  @State private var pingPongForward = true

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
          .scaleEffect(1 + sin(breathingPhase) * 0.012)
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
    .onChange(of: row) { advanceToRowStart() }
    .onReceive(
      Timer.publish(every: 1.0 / Double(row.framesPerSecond), on: .main, in: .common)
        .autoconnect()
    ) { _ in advanceFrame() }
  }

  private var breathingPhase: Double {
    Date().timeIntervalSinceReferenceDate * 1.6
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
    let rect = animState.frameRect(index: frameIndex)
    // 精灵图坐标系以左上角为原点；CGImage.cropping 使用左下角坐标系，需翻转 y。
    let flippedY = CGFloat(sheet.height) - rect.maxY
    let cropRect = CGRect(
      x: rect.minX,
      y: flippedY,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
    return sheet.cropping(to: cropRect) ?? sheet
  }

  private func advanceFrame() {
    let count = row.frameCount
    guard count > 1 else {
      frameIndex = 0
      return
    }
    if row.loopsPingPong {
      if pingPongForward {
        if frameIndex >= count - 1 {
          pingPongForward = false
          frameIndex -= 1
        } else {
          frameIndex += 1
        }
      } else {
        if frameIndex <= 0 {
          pingPongForward = true
          frameIndex += 1
        } else {
          frameIndex -= 1
        }
      }
    } else {
      frameIndex = (frameIndex + 1) % count
    }
  }

  private func advanceToRowStart() {
    frameIndex = 0
    pingPongForward = true
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
