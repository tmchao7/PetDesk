import SwiftUI

/// 设置里的提醒气泡预览：与悬浮窗 PetBubbleView 同款样式（毛玻璃 + 白描边 + 阴影）。
struct ReminderPreviewView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 13, weight: .semibold))
      .lineLimit(2)
      .multilineTextAlignment(.leading)
      .padding(13)
      .frame(width: 220, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7)))
      .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
  }
}
