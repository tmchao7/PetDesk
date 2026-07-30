import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetBubbleView: View {
  @ObservedObject var environment: AppEnvironment
  let showingQuickActions: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(2)
      HStack(spacing: 8) {
        if environment.snapshot.bubble == .stretchReminder {
          action("完成了", icon: "checkmark") { environment.acknowledgeActivityBreak() }
          action("10 分钟", icon: "clock") { environment.snoozeActivityReminder() }
        } else if environment.snapshot.bubble == .focusComplete {
          action("再来一次", icon: "arrow.clockwise") { environment.startFocus() }
        } else {
          action("专注", icon: "timer") { environment.startFocus() }
          action("静音", icon: environment.quietMode ? "speaker.wave.2" : "speaker.slash") {
            environment.quietMode.toggle()
          }
        }
      }
    }
    .padding(13)
    .frame(width: 220, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7)))
    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
  }

  private var title: String {
    switch environment.snapshot.bubble {
    case .focusComplete: "专注完成，辛苦了！"
    case .stretchReminder: "站起来活动一下吧。"
    case .focusInvite: "开始专注？"
    case nil: showingQuickActions ? "接下来做什么？" : ""
    }
  }

  private func action(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: 11, weight: .medium))
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }
}
