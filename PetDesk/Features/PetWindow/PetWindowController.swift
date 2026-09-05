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
  private var bubbleCancellable: AnyCancellable?
  private var scaleCancellable: AnyCancellable?
  private var dragPersistenceGate = PetWindowDragPersistenceGate()

  init(environment: AppEnvironment, positionStore: ScreenPositionStore = ScreenPositionStore()) {
    self.environment = environment
    self.positionStore = positionStore
    self.hostingView = PetHitTestHostingView(rootView: PetView(environment: environment))
    hostingView.petSize = environment.petAvatarSize
    let size = environment.petWindowSize
    let panel = PetPanel(contentRect: positionStore.restore(size: size, screens: NSScreen.screens))
    panel.contentView = hostingView
    panel.contentView?.wantsLayer = true
    panel.contentView?.layer?.masksToBounds = false
    super.init(window: panel)
    panel.delegate = self
    environment.updatePetWindowFrame(panel.frame)
    hostingView.onUserDragBegan = { [weak self] in
      self?.dragPersistenceGate.beginUserDrag()
    }
    hostingView.onUserDragEnded = { [weak self] in
      self?.finishUserDrag()
    }
    // 接收 Finder 拖入的文件，暂存到拖拽托盘。
    panel.registerForDraggedTypes([.fileURL])
    panel.onFilesDropped = { [weak environment] urls in
      environment?.addShelfItems(urls)
      environment?.shelfPanel?.orderFrontRegardless()
    }

    // bubbleVisible must be derived from both sources in one pipeline —
    // two separate sinks would overwrite each other (snapshot publishes
    // every second, clobbering the quickActions flag and breaking bubble
    // hit-testing).
    bubbleCancellable = environment.$quickActionsVisible
      .combineLatest(environment.$snapshot)
      .sink { [weak self] visible, snapshot in
        guard let self else { return }
        let isVisible = visible || snapshot.bubble != nil
        hostingView.bubbleVisible = isVisible
        // 自动时长提醒气泡只在悬浮窗内显示，不激活应用、不抢用户焦点。
        if case .stateDurationReminder? = snapshot.bubble { return }
        if isVisible {
          // Agent apps never become active on their own; activate explicitly
          // so the panel can become key and SwiftUI controls receive events.
          NSApp.activate(ignoringOtherApps: true)
          window?.makeKey()
        }
      }
    scaleCancellable = environment.$petScale.sink { [weak self] _ in
      guard let self else { return }
      // 窗口尺寸恒为 500×500，缩放只改宠物显示区（hit-test 与渲染都读它）。
      hostingView.petSize = environment.petAvatarSize
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) { nil }

  deinit {
    // selector 式观察者不会随 dealloc 自动移除，显式清理避免悬垂通知。
    NotificationCenter.default.removeObserver(self)
  }

  func showPet() {
    guard let window else { return }
    window.orderFrontRegardless()
    // Keep the panel key so clicks dispatch mouse events immediately
    // instead of being swallowed by window activation.
    window.makeKey()
    environment.updatePetAnimationPaused(false)
    AppLog.window.debug("Pet window shown")
  }

  func toggleVisibility() {
    guard let window else { return }
    if window.isVisible {
      environment.updatePetAnimationPaused(true)
      window.orderOut(nil)
    } else {
      showPet()
    }
  }

  func windowDidChangeOcclusionState(_ notification: Notification) {
    let isVisible = window?.occlusionState.contains(.visible) == true
    environment.updatePetAnimationPaused(!isVisible)
  }

  func windowDidMove(_ notification: Notification) {
    guard let frame = window?.frame, dragPersistenceGate.shouldPersistWindowMove else { return }
    persistWindowFrame(frame)
  }

  private func finishUserDrag() {
    dragPersistenceGate.endUserDrag()
    guard let frame = window?.frame else { return }
    persistWindowFrame(frame)
  }

  private func persistWindowFrame(_ frame: NSRect) {
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
