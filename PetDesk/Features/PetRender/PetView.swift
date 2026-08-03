import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetView: View {
  @ObservedObject var environment: AppEnvironment
  @State private var showingSpritesheetImporter = false
  @State private var importMessage: String?

  private var avatarSize: CGFloat { environment.petAvatarSize }
  /// 精灵帧为 192×208 竖构图，显示区保持同比例，避免方形裁剪。
  private var avatarHeight: CGFloat {
    avatarSize * SpriteSheetSpec.frameHeight / SpriteSheetSpec.frameWidth
  }
  private var cornerRadius: CGFloat { 20 * environment.petScale }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      // 固定宠物区域尺寸：没有显式 frame 时会撑满窗口居中。
      // 静态模式：直接渲染当前状态行，不做浮动/缩放/旋转微动作。
      petContent(phase: 0)
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
  private func petContent(phase: Double) -> some View {
    ZStack {
      AnimatedAvatarView(
        image: environment.avatarImage,
        spritesheet: environment.avatarSpritesheet,
        animState: PetAnimState.from(
          baseState: environment.snapshot.baseState,
          transient: environment.snapshot.transientState
        ),
        displayMode: environment.avatarDisplayMode,
        avatarSize: avatarSize
      )
      .frame(width: avatarSize, height: avatarHeight)
      OverlayEffectView(
        effects: environment.snapshot.effects,
        transient: environment.snapshot.transientState,
        scale: environment.petScale
      )
    }
    .scaleEffect(scale(for: phase))
    .rotationEffect(.degrees(rotation(for: phase)))
    .offset(y: verticalOffset(for: phase))
    .contentShape(
      environment.avatarDisplayMode == .circle
        ? AnyShape(Circle())
        : AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    )
    .onTapGesture {
      withAnimation(.snappy(duration: 0.22)) { environment.quickActionsVisible.toggle() }
    }
    .contextMenu {
      Button("待办事项", systemImage: "checklist") {
        environment.openTodoWindow?()
      }
      Button("导入精灵图…", systemImage: "square.grid.3x3") {
        // 悬浮窗是非激活面板，先切到 regular 让打开面板能正常弹出。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showingSpritesheetImporter = true
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
    .fileImporter(
      isPresented: $showingSpritesheetImporter,
      allowedContentTypes: [.png, .webP],
      allowsMultipleSelection: false
    ) { result in
      NSApp.setActivationPolicy(.accessory)
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task {
        importMessage = await environment.importSpritesheet(from: url)
      }
    }
    .alert(
      "导入精灵图",
      isPresented: Binding(
        get: { importMessage != nil },
        set: { if !$0 { importMessage = nil } }
      )
    ) {
      Button("好") { importMessage = nil }
    } message: {
      Text(importMessage ?? "")
    }
  }

  private func verticalOffset(for phase: Double) -> CGFloat {
    let amplitude: Double
    switch environment.snapshot.baseState {
    case .sleeping: amplitude = 2
    case .drinkingTea, .working, .focusing: amplitude = 3
    case .jogging: amplitude = 7
    case .running: amplitude = 10
    }
    if environment.snapshot.transientState == .celebrating { return CGFloat(-abs(sin(phase)) * 18) }
    return CGFloat(sin(phase) * amplitude)
  }

  private func rotation(for phase: Double) -> Double {
    if case .startled = environment.snapshot.transientState { return sin(phase * 3) * 5 }
    return switch environment.snapshot.baseState {
    case .jogging: sin(phase) * 2.5
    case .running: sin(phase) * 4
    default: 0
    }
  }

  private func scale(for phase: Double) -> CGFloat {
    if case .startled = environment.snapshot.transientState { return 1.08 }
    return CGFloat(1 + sin(phase) * 0.012)
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
