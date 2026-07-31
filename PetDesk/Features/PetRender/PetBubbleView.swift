import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetBubbleView: View {
  @ObservedObject var environment: AppEnvironment
  let showingQuickActions: Bool

  /// Incomplete todo items (max 5 shown in bubble).
  private var incompleteItems: [TodoItem] {
    Array(environment.todoItems.filter { !$0.isCompleted }.prefix(5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(2)

      if environment.snapshot.bubble == .stretchReminder {
        HStack(spacing: 8) {
          action("完成了", icon: "checkmark") { environment.acknowledgeActivityBreak() }
          action("10 分钟", icon: "clock") { environment.snoozeActivityReminder() }
        }
      } else if environment.snapshot.bubble == .focusComplete {
        HStack(spacing: 8) {
          action("再来一次", icon: "arrow.clockwise") { environment.startFocus() }
        }
      } else {
        if showingQuickActions || environment.snapshot.bubble == .focusInvite {
          if !incompleteItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(incompleteItems) { item in
                HStack(spacing: 6) {
                  Button {
                    environment.toggleTodoItem(id: item.id)
                  } label: {
                    Image(systemName: "circle")
                      .font(.system(size: 11))
                      .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)

                  Text(item.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
            }
          }

          HStack(spacing: 8) {
            action("专注", icon: "timer") { environment.startFocus() }
            action("摸鱼", icon: "cup.and.heat.waves") { environment.slackOff() }
            action("放松", icon: "leaf") { environment.relax() }
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
    Label(title, systemImage: icon)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .onTapGesture { action() }
  }
}
