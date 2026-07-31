import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetBubbleView: View {
  @ObservedObject var environment: AppEnvironment
  let showingQuickActions: Bool

  private var scale: Double { environment.petScale }
  private var bubbleWidth: CGFloat { 220 * scale }
  private var titleSize: CGFloat { 13 * scale }
  private var bodySize: CGFloat { 11 * scale }
  private var paddingSize: CGFloat { 13 * scale }
  private var spacingSize: CGFloat { 10 * scale }

  /// Incomplete todo items (max 5 shown in bubble).
  private var incompleteItems: [TodoItem] {
    Array(environment.todoItems.filter { !$0.isCompleted }.prefix(5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: spacingSize) {
      Text(title)
        .font(.system(size: titleSize, weight: .semibold))
        .lineLimit(2)

      if environment.snapshot.bubble == .stretchReminder {
        HStack(spacing: 8 * scale) {
          action("完成了", icon: "checkmark") { environment.acknowledgeActivityBreak() }
          action("10 分钟", icon: "clock") { environment.snoozeActivityReminder() }
        }
      } else if environment.snapshot.bubble == .focusComplete {
        HStack(spacing: 8 * scale) {
          action("再来一次", icon: "arrow.clockwise") { environment.startFocus() }
        }
      } else {
        if showingQuickActions || environment.snapshot.bubble == .focusInvite {
          if !incompleteItems.isEmpty {
            VStack(alignment: .leading, spacing: 4 * scale) {
              ForEach(incompleteItems) { item in
                HStack(spacing: 6 * scale) {
                  Button {
                    environment.toggleTodoItem(id: item.id)
                  } label: {
                    Image(systemName: "circle")
                      .font(.system(size: bodySize))
                      .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)

                  Text(item.title)
                    .font(.system(size: bodySize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
            }
          }

          HStack(spacing: 8 * scale) {
            action("专注", icon: "timer") { environment.startFocus() }
            action("摸鱼", icon: "cup.and.heat.waves") { environment.slackOff() }
            action("放松", icon: "leaf") { environment.relax() }
          }
        }
      }
    }
    .padding(paddingSize)
    .frame(width: bubbleWidth, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8 * scale))
    .overlay(RoundedRectangle(cornerRadius: 8 * scale).stroke(.white.opacity(0.7)))
    .shadow(color: .black.opacity(0.14), radius: 10 * scale, y: 5 * scale)
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
      .font(.system(size: bodySize, weight: .medium))
      .padding(.horizontal, 10 * scale)
      .padding(.vertical, 4 * scale)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 6 * scale))
      .contentShape(RoundedRectangle(cornerRadius: 6 * scale))
      .onTapGesture { action() }
  }
}
