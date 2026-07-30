import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetView: View {
  @ObservedObject var environment: AppEnvironment

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let phase = timeline.date.timeIntervalSinceReferenceDate * animationSpeed
      ZStack(alignment: .bottomTrailing) {
        if environment.quickActionsVisible || environment.snapshot.bubble != nil {
          PetBubbleView(
            environment: environment, showingQuickActions: environment.quickActionsVisible
          )
          .offset(x: -78, y: -142)
          .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
        }

        ZStack {
          AvatarView(image: environment.avatarImage)
            .frame(width: 148, height: 148)
          OverlayEffectView(
            effects: environment.snapshot.effects,
            transient: environment.snapshot.transientState
          )
        }
        .scaleEffect(scale(for: phase))
        .rotationEffect(.degrees(rotation(for: phase)))
        .offset(y: verticalOffset(for: phase))
        .contentShape(Circle())
        .onTapGesture {
          withAnimation(.snappy(duration: 0.22)) { environment.quickActionsVisible.toggle() }
        }
        .contextMenu {
          Button("Start Focus", systemImage: "timer") { environment.startFocus() }
          Button(
            environment.quietMode ? "Disable Quiet Mode" : "Enable Quiet Mode",
            systemImage: "speaker.slash"
          ) {
            environment.quietMode.toggle()
          }
        }
      }
      .frame(width: 320, height: 260, alignment: .bottomTrailing)
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
