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
  let avatarSize: CGFloat

  /// 帧缓存：裁剪是 O(1) 但 NSImage 包装/释放有分配流量，状态切换时复用。
  /// cachedFrameSheet 强引用精灵图，保证缓存命中比较时其地址不被复用。
  @State private var cachedFrameSheet: CGImage?
  @State private var cachedFrame: (sheetID: UInt, row: AnimationRow, index: Int, image: NSImage)?

  private var row: AnimationRow { animState.row }

  /// 精灵帧是 192×208 竖构图，按同比例放大显示，避免方形框 scaledToFill
  /// 把上下边缘裁掉（角色会显得小、头脚被切）。
  private var spriteSize: CGSize {
    CGSize(
      width: avatarSize,
      height: avatarSize * SpriteSheetSpec.frameHeight / SpriteSheetSpec.frameWidth
    )
  }

  var body: some View {
    Group {
      if let spritesheet {
        spriteView(spritesheet)
      } else if let image {
        card {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
        }
      } else {
        card { placeholder }
      }
    }
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
  }

  /// 精灵图路径：保持 192×208 比例、无边框无卡片，背景完全透明，
  /// 只给角色本体加一点投影，在浅色桌面上仍可辨认。
  private func spriteView(_ sheet: CGImage) -> some View {
    Image(nsImage: cachedFrameImage(from: sheet))
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .frame(width: spriteSize.width, height: spriteSize.height)
      .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
  }

  /// 无精灵图时的卡片样式（保持原有圆形/圆角外观）。
  private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .clipShape(
        displayMode == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20))
      )
      .overlay(
        (displayMode == .circle
          ? AnyShape(Circle())
          : AnyShape(RoundedRectangle(cornerRadius: 20))).stroke(.white, lineWidth: 5)
      )
      .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
  }

  private var placeholder: some View {
    ZStack {
      Circle().fill(Color(red: 0.96, green: 0.82, blue: 0.72))
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 76, weight: .regular))
        .foregroundStyle(.white.opacity(0.92))
    }
  }

  /// 按当前状态行裁剪基准帧（静态模式，不做帧动画），结果按
  /// (精灵图地址, 行, 帧索引) 缓存复用。精灵图规范与 CGImage.cropping
  /// 同为“y=0 在视觉顶部”，直接按行/列裁剪，不做 y 翻转。
  private func cachedFrameImage(from sheet: CGImage) -> NSImage {
    let sheetID = UInt(bitPattern: Unmanaged.passUnretained(sheet).toOpaque())
    let index = staticFrameIndex
    if let cached = cachedFrame, cached.sheetID == sheetID, cached.row == row,
      cached.index == index
    {
      return cached.image
    }
    let rect = animState.frameRect(index: index)
    let cropRect = CGRect(
      x: rect.minX,
      y: rect.minY,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
    let cropped = sheet.cropping(to: cropRect) ?? sheet
    let image = NSImage(
      cgImage: cropped,
      size: NSSize(width: SpriteSheetSpec.frameWidth, height: SpriteSheetSpec.frameHeight)
    )
    // 先强引用精灵图再缓存，保证地址在命中比较期间不被复用。
    cachedFrameSheet = sheet
    cachedFrame = (sheetID, row, index, image)
    return image
  }

  /// 静态模式下每个状态行显示的基准帧（避开眨眼/位移/旋转帧）。
  private var staticFrameIndex: Int {
    switch row {
    case .happy, .surprised: 1
    default: 0
    }
  }
}
