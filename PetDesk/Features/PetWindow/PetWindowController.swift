import AppKit
import Combine
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

@MainActor
final class PetWindowController: NSWindowController, NSWindowDelegate {
  private let environment: AppEnvironment
  private let positionStore: ScreenPositionStore
  private let hostingView: PetHitTestHostingView<PetView>
  private var snapshotCancellable: AnyCancellable?
  private var quickActionsCancellable: AnyCancellable?
  private var scaleCancellable: AnyCancellable?

  init(environment: AppEnvironment, positionStore: ScreenPositionStore = ScreenPositionStore()) {
    self.environment = environment
    self.positionStore = positionStore
    self.hostingView = PetHitTestHostingView(rootView: PetView(environment: environment))
    let size = environment.petWindowSize
    let panel = PetPanel(contentRect: positionStore.restore(size: size, screens: NSScreen.screens))
    panel.contentView = hostingView
    panel.contentView?.wantsLayer = true
    panel.contentView?.layer?.masksToBounds = false
    super.init(window: panel)
    panel.delegate = self
    environment.updatePetWindowFrame(panel.frame)

    snapshotCancellable = environment.$snapshot.sink { [weak hostingView] snapshot in
      hostingView?.bubbleVisible = snapshot.bubble != nil
    }
    quickActionsCancellable = environment.$quickActionsVisible.sink { [weak self] visible in
      guard let self else { return }
      hostingView.bubbleVisible = visible || environment.snapshot.bubble != nil
      if hostingView.bubbleVisible {
        // Agent apps never become active on their own; activate explicitly so
        // the panel can become key and SwiftUI controls receive events.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
      }
    }
    scaleCancellable = environment.$petScale.sink { [weak self] scale in
      guard let self, let window = self.window else { return }
      hostingView.petSize = environment.petAvatarSize
      let newSize = environment.petWindowSize
      guard window.frame.size != newSize else { return }
      let origin = window.frame.origin
      window.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: true)
      self.environment.updatePetWindowFrame(window.frame)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) { nil }

  func showPet() {
    guard let window else { return }
    window.orderFrontRegardless()
    AppLog.window.debug("Pet window shown")
  }

  func toggleVisibility() {
    guard let window else { return }
    window.isVisible ? window.orderOut(nil) : showPet()
  }

  func windowDidMove(_ notification: Notification) {
    guard let frame = window?.frame else { return }
    positionStore.save(frame: frame)
    environment.updatePetWindowFrame(frame)
  }

  private func clampToVisibleScreens() {
    guard let window else { return }
    let frame = ScreenPositionResolver.clamped(
      frame: window.frame,
      visibleFrames: NSScreen.screens.map(\.visibleFrame)
    )
    window.setFrame(frame, display: true, animate: true)
    environment.updatePetWindowFrame(frame)
  }

  @objc private func screenParametersChanged() {
    clampToVisibleScreens()
  }
}
