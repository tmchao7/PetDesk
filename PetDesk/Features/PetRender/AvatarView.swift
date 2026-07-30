import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct AvatarView: View {
  let image: NSImage?
  var displayMode: AvatarDisplayMode = .circle

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        ZStack {
          Circle().fill(Color(red: 0.96, green: 0.82, blue: 0.72))
          Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 76, weight: .regular))
            .foregroundStyle(.white.opacity(0.92))
        }
      }
    }
    .clipShape(
      displayMode == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20))
    )
    .overlay(
      (displayMode == .circle
        ? AnyShape(Circle())
        : AnyShape(RoundedRectangle(cornerRadius: 20))).stroke(.white, lineWidth: 5)
    )
    .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
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
