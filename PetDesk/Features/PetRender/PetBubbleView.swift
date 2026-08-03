import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct PetBubbleView: View {
  @ObservedObject var environment: AppEnvironment
  let showingQuickActions: Bool

  /// 气泡待办：全部未完成项（列表区可双指/滚轮上下滚动翻看）。
  private var incompleteItems: [TodoItem] {
    environment.incompleteTodoItems
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
        if showingQuickActions {
          if !incompleteItems.isEmpty {
            // 待办多时列表区可双指/滚轮上下滚动翻看（上限 160pt，约 7 行）。
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 4) {
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
              // 右侧留白：滚动条 overlay 悬停在此区域，不遮挡待办文字。
              .padding(.trailing, 14)
            }
            .frame(maxHeight: 160)
            .scrollBounceBehavior(.basedOnSize)
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
    .accessibilityIdentifier("pet.bubble")
  }

  private var title: String {
    switch environment.snapshot.bubble {
    case .focusComplete: "专注完成，辛苦了！"
    case .stretchReminder: "站起来活动一下吧。"
    case .stateDurationReminder(let text): text
    case nil: showingQuickActions ? "接下来做什么？" : ""
    }
  }

  private func action(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    // 统一排版：图标在上、文字在下，等宽等高
    VStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .semibold))
      Text(title)
        .font(.system(size: 10, weight: .medium))
    }
    .frame(width: 52, height: 44)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture { action() }
  }
}
