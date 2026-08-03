import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct OverlayEffectView: View {
  let effects: Set<PetEffect>
  let transient: TransientPetState?
  let scale: Double

  private var iconSize: CGFloat { 25 * scale }

  var body: some View {
    ZStack {
      if effects.contains(.sweat) {
        prop("drop.fill", color: .cyan, x: 68 * scale, y: -52 * scale)
      }
      if effects.contains(.smoke) {
        prop("cloud.fog.fill", color: .gray, x: 0, y: -92 * scale)
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
