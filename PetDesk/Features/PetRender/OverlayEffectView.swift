import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct OverlayEffectView: View {
  let effects: Set<PetEffect>
  let transient: TransientPetState?
  let scale: Double

  private var iconSize: CGFloat { 25 * scale }
  private var zzzSize: CGFloat { 22 * scale }

  var body: some View {
    ZStack {
      if effects.contains(.tea) {
        prop("cup.and.saucer.fill", color: .brown, x: 62 * scale, y: 54 * scale)
      }
      if effects.contains(.keyboard) {
        prop("keyboard", color: .secondary, x: 0, y: 72 * scale)
      }
      if effects.contains(.sweat) {
        prop("drop.fill", color: .cyan, x: 68 * scale, y: -52 * scale)
      }
      if effects.contains(.smoke) {
        prop("cloud.fog.fill", color: .gray, x: 0, y: -92 * scale)
      }
      if effects.contains(.zzz) {
        // 睡觉表情：月亮 + Zzz，带柔和浮动动画
        Image(systemName: "moon.zzz.fill")
          .font(.system(size: 32 * scale, weight: .semibold))
          .foregroundStyle(.indigo)
          .shadow(color: .indigo.opacity(0.45), radius: 5)
          .offset(x: 62 * scale, y: -72 * scale)
          .modifier(SleepFloatAnimation(scale: scale))
      }
      if case .startled = transient {
        prop("bell.badge.fill", color: .red, x: -70 * scale, y: -68 * scale)
      }
      if transient == .celebrating {
        prop("sparkles", color: .yellow, x: -68 * scale, y: -70 * scale)
      }
      if transient == .stretching {
        prop("figure.cooldown", color: .green, x: -72 * scale, y: -62 * scale)
      }
    }
    .allowsHitTesting(false)
  }

  private func prop(_ systemName: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
    Image(systemName: systemName)
      .font(.system(size: iconSize, weight: .semibold))
      .foregroundStyle(color)
      .padding(7 * scale)
      .background(.regularMaterial, in: Circle())
      .offset(x: x, y: y)
  }
}

/// 让睡觉表情缓慢上下浮动，模拟呼吸节奏。
private struct SleepFloatAnimation: ViewModifier {
  let scale: Double
  @State private var floating = false

  func body(content: Content) -> some View {
    content
      .offset(y: floating ? -7 * scale : 5 * scale)
      .animation(
        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
        value: floating
      )
      .onAppear { floating = true }
  }
}
