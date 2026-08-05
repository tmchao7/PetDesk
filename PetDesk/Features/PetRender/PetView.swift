import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetView: View {
  @ObservedObject var environment: AppEnvironment

  private var avatarSize: CGFloat { environment.petAvatarSize }
  /// 精灵帧为 192×208 竖构图，显示区保持同比例，避免方形裁剪。
  private var avatarHeight: CGFloat {
    avatarSize * SpriteSheetSpec.frameHeight / SpriteSheetSpec.frameWidth
  }
  private var cornerRadius: CGFloat { 20 * environment.petScale }
  /// CALayer 播放用的预切片帧（AnimationFrameStore 按行/帧数缓存复用）。
  @State private var layerFrameStore = AnimationFrameStore()

  /// 多帧动画的 CGImage 帧列表（供 CALayer 播放器）。
  private func animationFrames(sheet: CGImage, row: AnimationRow, count: Int) -> [CGImage] {
    layerFrameStore.preload(sheet: sheet, row: row, frameCount: count).cgImages
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      // 固定宠物区域尺寸：没有显式 frame 时会撑满窗口居中。
      // 静态模式：直接渲染当前状态行，不做浮动/缩放/旋转微动作。
      petContent()
        .frame(width: avatarSize, height: avatarHeight)

      if environment.quickActionsVisible || environment.snapshot.bubble != nil {
        PetBubbleView(
          environment: environment, showingQuickActions: environment.quickActionsVisible
        )
        .offset(x: -20, y: -(avatarHeight + 20))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
  }

  @ViewBuilder
  private func petContent() -> some View {
    let animState = PetAnimState.from(
      baseState: environment.snapshot.baseState,
      transient: environment.snapshot.transientState
    )
    let frameCount = environment.multiFrameCount(for: animState.row)
    ZStack {
      if let spritesheet = environment.avatarSpritesheet, frameCount > 1 {
        // 多帧动画：CALayer 播放器（离散帧、幂等更新、暂停零工作）。
        // 帧已由 AnimationFrameStore 预切片，播放期间无 crop 无 NSImage 包装。
        let frames = animationFrames(sheet: spritesheet, row: animState.row, count: frameCount)
        PetLayerRendererRepresentable(
          images: frames,
          avatarSize: avatarSize,
          isPaused: environment.isPetAnimationPaused,
          baseFrameDuration: environment.animationBaseFrameDuration,
          speed: environment.animationPlaybackSpeed
        )
        .frame(width: avatarSize, height: avatarHeight)
        .accessibilityLabel("Pet avatar")
        .accessibilityIdentifier("pet.avatar")
      } else {
        // 静态头像 / 单帧姿势：低成本 SwiftUI Image 路径。
        AnimatedAvatarView(
          image: environment.avatarImage,
          spritesheet: environment.avatarSpritesheet,
          animState: animState,
          displayMode: environment.avatarDisplayMode,
          avatarSize: avatarSize,
          multiFrameCount: frameCount,
          cpuProvider: { environment.latestCPU },
          isPaused: environment.isPetAnimationPaused,
          speedMultiplier: environment.animationSpeedMultiplier
        )
        .frame(width: avatarSize, height: avatarHeight)
      }
      OverlayEffectView(
        effects: environment.snapshot.effects,
        transient: environment.snapshot.transientState,
        scale: environment.petScale
      )
    }
    // 静态模式无相位动画：sin 类浮动/旋转全部恒等，只保留受惊的放大反馈。
    .scaleEffect(startledScale)
    .contentShape(
      environment.avatarDisplayMode == .circle
        ? AnyShape(Circle())
        : AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    )
    .onTapGesture {
      environment.petInteraction()
      withAnimation(.snappy(duration: 0.22)) { environment.quickActionsVisible.toggle() }
    }
    .contextMenu {
      Button("待办事项", systemImage: "checklist") {
        environment.openTodoWindow?()
      }
      Button("使用统计", systemImage: "chart.bar.fill") {
        environment.openStatsWindow?()
      }
      Button("设置", systemImage: "gearshape") {
        environment.openSettings?()
      }
      Divider()
      Button("隐藏桌宠", systemImage: "eye.slash") {
        environment.hidePet?()
      }
    }
  }

  /// 受惊反馈：仅放大，不做动画（静态模式的唯一非恒等变换）。
  private var startledScale: CGFloat {
    if case .startled = environment.snapshot.transientState { return 1.08 }
    return 1.0
  }
}
