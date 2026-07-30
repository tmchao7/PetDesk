import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct AvatarEditorView: View {
  let sourceImage: NSImage
  let onConfirm: (CGImage) -> Void
  let onCancel: () -> Void

  @State private var panOffset: CGSize = .zero
  @State private var zoomScale: CGFloat = 1.0
  @State private var displayMode: AvatarDisplayMode = .circle

  private let cropSize: CGFloat = 240

  var body: some View {
    VStack(spacing: 16) {
      Text("Adjust your avatar")
        .font(.headline)

      ZStack {
        Image(nsImage: sourceImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: cropSize, height: cropSize)
          .scaleEffect(zoomScale)
          .offset(panOffset)
          .clipped()
          .gesture(magnificationGesture.simultaneously(with: dragGesture))

        if displayMode == .circle {
          Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: cropSize, height: cropSize)
            .allowsHitTesting(false)
        }
      }
      .frame(width: cropSize, height: cropSize)
      .clipShape(displayMode == .circle ? AnyShape(Circle()) : AnyShape(Rectangle()))
      .shadow(color: .black.opacity(0.18), radius: 9, y: 5)

      HStack(spacing: 12) {
        Button("Reset") {
          withAnimation {
            panOffset = .zero
            zoomScale = 1.0
          }
        }
        .buttonStyle(.bordered)
        .disabled(panOffset == .zero && zoomScale == 1.0)

        Picker("Shape", selection: $displayMode) {
          Image(systemName: "circle").tag(AvatarDisplayMode.circle)
          Image(systemName: "square").tag(AvatarDisplayMode.original)
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
      }

      HStack(spacing: 12) {
        Button("Cancel", role: .cancel) { onCancel() }
          .buttonStyle(.bordered)
          .keyboardShortcut(.cancelAction)

        Button("Use Avatar") { confirmCrop() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 320)
  }

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        zoomScale = max(1.0, min(value, 5.0))
      }
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        let maxPan = (zoomScale - 1.0) * cropSize / 2
        panOffset = CGSize(
          width: max(-maxPan, min(maxPan, value.translation.width)),
          height: max(-maxPan, min(maxPan, value.translation.height))
        )
      }
  }

  private func confirmCrop() {
    guard
      let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }

    if let cropped = AvatarCropper.crop(
      image: cgImage,
      viewSize: cropSize,
      panOffset: panOffset,
      zoomScale: zoomScale,
      outputSize: 1024
    ) {
      onConfirm(cropped)
    }
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
