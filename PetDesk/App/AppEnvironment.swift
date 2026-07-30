import AppKit
import Combine
import Foundation

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

@MainActor
final class AppEnvironment: ObservableObject {
  @Published private(set) var snapshot = PetSnapshot()
  @Published private(set) var avatarImage: NSImage?
  @Published private(set) var focusSession = FocusSession()
  @Published var quickActionsVisible = false
  @Published private(set) var petWindowFrame: CGRect?
  @Published var quietMode: Bool {
    didSet { defaults.set(quietMode, forKey: Keys.quietMode) }
  }
  @Published private(set) var avatarError: String?
  @Published private(set) var avatarSourceImage: CGImage?
  @Published var avatarDisplayMode: AvatarDisplayMode {
    didSet { defaults.set(avatarDisplayMode.rawValue, forKey: Keys.avatarDisplayMode) }
  }

  let diagnostics = DiagnosticRecorder()
  let notificationCapability: NotificationCapability

  private enum Keys {
    static let quietMode = "quietMode"
    static let avatarDisplayMode = "avatarDisplayMode"
  }

  private let defaults: UserDefaults
  private let avatarRepository: AvatarRepository?
  private let signalSources: [any PetSignalSource]
  private var machine = PetStateMachine()
  private var activityReminder = ActivityReminderAccumulator()
  private var latestIdle: Duration = .zero
  private var tasks: [Task<Void, Never>] = []
  private var reminderWasDue = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.quietMode = defaults.bool(forKey: Keys.quietMode)
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    let notificationMonitor = AccessibilityNotificationPulseMonitor()
    self.notificationCapability = notificationMonitor.capability
    self.signalSources = [SystemLoadMonitor(), UserIdleMonitor(), notificationMonitor]
    self.avatarRepository = try? AvatarRepository()
  }

  init(
    defaults: UserDefaults = .standard,
    signalSources: [any PetSignalSource],
    notificationCapability: NotificationCapability = .unsupported(.sourceApplicationUnavailable),
    avatarRepository: AvatarRepository? = nil
  ) {
    self.defaults = defaults
    self.quietMode = defaults.bool(forKey: Keys.quietMode)
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    self.notificationCapability = notificationCapability
    self.signalSources = signalSources
    self.avatarRepository = avatarRepository
  }

  func start() {
    guard tasks.isEmpty else { return }
    for source in signalSources {
      tasks.append(
        Task { [weak self] in
          for await event in source.events() {
            guard !Task.isCancelled else { break }
            self?.handle(event)
          }
        })
    }
    tasks.append(
      Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(1))
          guard !Task.isCancelled else { break }
          self?.advanceOneSecond()
        }
      })
    tasks.append(Task { [weak self] in await self?.loadStoredAvatar() })
    diagnostics.record(category: "app", message: "started")
    AppLog.app.info("PetDesk started")
  }

  func stop() {
    for task in tasks {
      task.cancel()
    }
    tasks.removeAll()
    diagnostics.record(category: "app", message: "stopped")
  }

  func startFocus() {
    focusSession.start()
    handle(.focusCommand(.start))
    diagnostics.record(category: "focus", message: "session-started")
    AppLog.focus.info("Focus session started")
  }

  func cancelFocus() {
    focusSession.cancel()
    handle(.focusCommand(.cancel))
    diagnostics.record(category: "focus", message: "session-cancelled")
  }

  func snoozeActivityReminder() {
    activityReminder.snooze()
    reminderWasDue = false
    handle(.focusCommand(.snoozeActivity))
    diagnostics.record(category: "focus", message: "activity-reminder-snoozed")
  }

  func acknowledgeActivityBreak() {
    activityReminder.acknowledgeBreak()
    reminderWasDue = false
    handle(.focusCommand(.snoozeActivity))
    diagnostics.record(category: "focus", message: "activity-break-acknowledged")
  }

  func importAvatar(from url: URL) async {
    guard let avatarRepository else {
      avatarError = "Avatar storage is unavailable."
      return
    }
    do {
      let storedURL = try await avatarRepository.importAvatar(from: url)
      avatarImage = AvatarImageLoader.load(from: storedURL)
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-imported")
      AppLog.avatar.info("Avatar imported")
    } catch let error as AvatarImportError {
      avatarError = Self.avatarMessage(for: error)
      diagnostics.record(category: "avatar", message: "avatar-import-failed")
      AppLog.avatar.error("Avatar import failed")
    } catch {
      avatarError = "The image could not be imported."
      diagnostics.record(category: "avatar", message: "avatar-import-failed")
      AppLog.avatar.error("Avatar import failed")
    }
  }

  func loadSourceForEdit(from url: URL) async {
    guard let avatarRepository else {
      avatarError = "Avatar storage is unavailable."
      return
    }
    do {
      let image = try await avatarRepository.loadSourceImage(from: url)
      avatarSourceImage = image
      avatarError = nil
    } catch let error as AvatarImportError {
      avatarError = Self.avatarMessage(for: error)
    } catch {
      avatarError = "The image could not be loaded."
    }
  }

  func saveCroppedAvatar(_ image: CGImage) async {
    guard let avatarRepository else {
      avatarError = "Avatar storage is unavailable."
      return
    }
    do {
      let storedURL = try await avatarRepository.saveAvatar(image)
      avatarImage = AvatarImageLoader.load(from: storedURL)
      avatarSourceImage = nil
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-cropped")
      AppLog.avatar.info("Avatar cropped and saved")
    } catch {
      avatarError = "The cropped image could not be saved."
      diagnostics.record(category: "avatar", message: "avatar-crop-failed")
    }
  }

  func resetAvatar() async {
    guard let avatarRepository else { return }
    do {
      try await avatarRepository.resetAvatar()
      avatarImage = nil
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-reset")
    } catch {
      avatarError = "Could not reset avatar."
    }
  }

  func injectNotification(_ source: NotificationSource) {
    handle(.notificationPulse(source))
  }

  func updatePetWindowFrame(_ frame: CGRect) {
    petWindowFrame = frame
  }

  func applyDemoState(_ name: String) {
    switch name {
    case "sleeping": handle(.userIdleChanged(.seconds(301)))
    case "working": feedDemoCPU(0.50)
    case "jogging": feedDemoCPU(0.70)
    case "running": feedDemoCPU(0.90)
    case "focusing": startFocus()
    default: break
    }
  }

  private func handle(_ event: PetEvent) {
    if case .userIdleChanged(let duration) = event { latestIdle = duration }
    if quietMode, case .notificationPulse = event { return }
    snapshot = machine.reduce(event, elapsed: eventElapsed(event))
    if case .tick = event {
    } else {
      diagnostics.record(
        category: "stateMachine",
        message: "event=\(eventName(event)) state=\(snapshot.baseState.rawValue)"
      )
    }
  }

  private func advanceOneSecond() {
    handle(.tick(.seconds(1)))
    let previousPhase = focusSession.phase
    focusSession.advance(by: .seconds(1), userIdle: latestIdle)
    if previousPhase != .completed, focusSession.phase == .completed {
      handle(.focusCommand(.complete))
    }

    activityReminder.advance(by: .seconds(1), userIdle: latestIdle)
    if activityReminder.isDue, !reminderWasDue, !quietMode {
      reminderWasDue = true
      handle(.focusCommand(.showActivityReminder))
    }
  }

  private func loadStoredAvatar() async {
    guard let avatarRepository else { return }
    let url = await avatarRepository.avatarURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    avatarImage = AvatarImageLoader.load(from: url)
  }

  private func feedDemoCPU(_ load: Double) {
    for _ in 0..<10 {
      handle(.systemMetrics(SystemMetrics(cpuLoad: load, thermalLevel: .nominal)))
    }
  }

  private func eventElapsed(_ event: PetEvent) -> Duration {
    switch event {
    case .systemMetrics: .seconds(1)
    case .tick(let duration): duration
    default: .zero
    }
  }

  private func eventName(_ event: PetEvent) -> String {
    switch event {
    case .systemMetrics: "systemMetrics"
    case .userIdleChanged: "userIdleChanged"
    case .notificationPulse: "notificationPulse"
    case .focusCommand: "focusCommand"
    case .tick: "tick"
    }
  }

  private static func avatarMessage(for error: AvatarImportError) -> String {
    switch error {
    case .fileTooLarge: "Choose an image smaller than 20 MB."
    case .unsupportedType: "Choose a PNG, JPEG, or HEIC image."
    case .unreadableImage: "The selected file is not a readable image."
    case .encodingFailed: "The image could not be saved."
    }
  }
}
