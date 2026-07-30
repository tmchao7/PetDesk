import AppKit

@MainActor
final class PetPanel: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    hidesOnDeactivate = false
    isMovableByWindowBackground = true
    animationBehavior = .utilityWindow
    acceptsMouseMovedEvents = true
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
