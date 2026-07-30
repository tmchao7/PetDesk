import AppKit
import SwiftUI

struct AvatarView: View {
  let image: NSImage?

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
    .clipShape(Circle())
    .overlay(Circle().stroke(.white, lineWidth: 5))
    .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
  }
}
