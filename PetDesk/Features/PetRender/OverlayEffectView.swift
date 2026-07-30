import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct OverlayEffectView: View {
  let effects: Set<PetEffect>
  let transient: TransientPetState?

  var body: some View {
    ZStack {
      if effects.contains(.tea) {
        prop("cup.and.saucer.fill", color: .brown, x: 62, y: 54)
      }
      if effects.contains(.keyboard) {
        prop("keyboard", color: .secondary, x: 0, y: 72)
      }
      if effects.contains(.sweat) {
        prop("drop.fill", color: .cyan, x: 68, y: -52)
      }
      if effects.contains(.smoke) {
        prop("cloud.fog.fill", color: .gray, x: 0, y: -92)
      }
      if effects.contains(.zzz) {
        Text("Zzz")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.indigo)
          .offset(x: 62, y: -72)
      }
      if case .startled = transient {
        prop("bell.badge.fill", color: .red, x: -70, y: -68)
      }
      if transient == .celebrating {
        prop("sparkles", color: .yellow, x: -68, y: -70)
      }
      if transient == .stretching {
        prop("figure.cooldown", color: .green, x: -72, y: -62)
      }
    }
    .allowsHitTesting(false)
  }

  private func prop(_ systemName: String, color: Color, x: CGFloat, y: CGFloat) -> some View {
    Image(systemName: systemName)
      .font(.system(size: 25, weight: .semibold))
      .foregroundStyle(color)
      .padding(7)
      .background(.regularMaterial, in: Circle())
      .offset(x: x, y: y)
  }
}
