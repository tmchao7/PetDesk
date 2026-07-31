import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetView: View {
  @ObservedObject var environment: AppEnvironment

  private var avatarSize: CGFloat { environment.petAvatarSize }
  private var cornerRadius: CGFloat { 20 * environment.petScale }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let phase = timeline.date.timeIntervalSinceReferenceDate * animationSpeed
      VStack(alignment: .trailing, spacing: -14) {
        if environment.quickActionsVisible || environment.snapshot.bubble != nil {
          PetBubbleView(
            environment: environment, showingQuickActions: environment.quickActionsVisible
          )
          .zIndex(1)
          .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
        }
        petContent(phase: phase)
      }
      .padding(40)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
  }

  @ViewBuilder
  private func petContent(phase: Double) -> some View {
    ZStack {
      AvatarView(image: environment.avatarImage, displayMode: environment.avatarDisplayMode)
        .frame(width: avatarSize, height: avatarSize)
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

      Button("设置", systemImage: "gearshape") {
        environment.openSettings?()
      }

      Divider()

      Button("隐藏桌宠", systemImage: "eye.slash") {
        environment.hidePet?()
      }
    }
  }

  private var animationSpeed: Double {
    switch environment.snapshot.baseState {
    case .sleeping: 1.2
    case .drinkingTea, .working, .focusing: 2.0
    case .jogging: 5.0
    case .running: 8.0
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
