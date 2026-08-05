import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// SwiftUI 到 CALayer 播放器的最小桥接：
/// 只接收已准备好的帧、尺寸、暂停与速度，不采样 CPU、不读文件、不选状态。
struct PetLayerRendererRepresentable: NSViewRepresentable {
  let images: [CGImage]
  let avatarSize: CGFloat
  let isPaused: Bool
  let frameDuration: TimeInterval

  func makeNSView(context: Context) -> PetLayerRenderer {
    let view = PetLayerRenderer()
    view.frame = NSRect(
      x: 0, y: 0,
      width: avatarSize,
      height: avatarSize * SpriteSheetSpec.frameHeight / SpriteSheetSpec.frameWidth
    )
    return view
  }

  func updateNSView(_ nsView: PetLayerRenderer, context: Context) {
    let config = PetLayerAnimationConfiguration(
      frameCount: images.count,
      frameDuration: frameDuration,
      isPaused: isPaused
    )
    nsView.update(images: images, config: config)
  }
}
