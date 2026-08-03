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
  @Published private(set) var avatarSpritesheet: CGImage?
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
  @Published var petScale: Double {
    didSet { defaults.set(petScale, forKey: Keys.petScale) }
  }
  /// 宠物窗口不可见或被遮挡时为 true，视图据此暂停帧动画与 Timeline 驱动。
  @Published private(set) var isPetAnimationPaused = true

  /// Base avatar size (148 pt at 1.0× scale).
  var petAvatarSize: CGFloat { 148 * petScale }
  /// Window size — generous to prevent bubble/effect clipping.
  var petWindowSize: NSSize { NSSize(width: 500, height: 500) }

  let diagnostics = DiagnosticRecorder()
  let notificationCapability: NotificationCapability

  /// Set by PetDeskApp to relay `@Environment(\.openSettings)` into the view
  /// hierarchy (e.g. context menus) where the environment is unavailable.
  var openSettings: (() -> Void)?
  /// Set by PetDeskApp to relay `@Environment(\.openWindow)` similarly.
  var openDiagnosticsWindow: (() -> Void)?
  /// Set by PetDeskApp — hides the floating pet window.
  var hidePet: (() -> Void)?
  /// Set by PetDeskApp — opens the Todo window.
  var openTodoWindow: (() -> Void)?
  /// Set by PetDeskApp — opens the usage stats window.
  var openStatsWindow: (() -> Void)?
  @Published var todoItems: [TodoItem] = []
  @Published var usageStatsByDay: [String: DayStats] = [:]

  private enum Keys {
    static let quietMode = "quietMode"
    static let avatarDisplayMode = "avatarDisplayMode"
    static let petScale = "petScale"
  }

  private let defaults: UserDefaults
  private let avatarRepository: AvatarRepository?
  private let todoStore: TodoStore?
  private let usageStore: UsageStatsStore?
  /// AI 姿态生成器（可选；未配置时使用本地程序化方案）。
  private var poseProvider: (any AIPoseProvider)?
  private let eyeLocator: (any EyeBandLocating)?
  private let signalSources: [any PetSignalSource]
  private var machine = PetStateMachine()
  private var activityReminder = ActivityReminderAccumulator()
  private var latestIdle: Duration = .zero
  private var forcedSleepRemaining: Duration = .zero
  private var currentDayKey = DayStats.todayKey()
  private var dayAccumulator = DayStats(date: DayStats.todayKey())
  private var secondsSinceStatsFlush = 0
  private var tasks: [Task<Void, Never>] = []
  private var reminderWasDue = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.quietMode = defaults.bool(forKey: Keys.quietMode)
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    let storedScale = defaults.double(forKey: Keys.petScale)
    self.petScale = storedScale > 0 ? storedScale : 1.0
    let notificationMonitor = AccessibilityNotificationPulseMonitor()
    self.notificationCapability = notificationMonitor.capability
    self.signalSources = [SystemLoadMonitor(), UserIdleMonitor(), notificationMonitor]
    self.avatarRepository = try? AvatarRepository()
    self.todoStore = try? TodoStore()
    self.usageStore = try? UsageStatsStore()
    self.eyeLocator = VisionEyeBandLocator()
    self.poseProvider = GPTImage2Provider.fromEnvironment()
  }

  init(
    defaults: UserDefaults = .standard,
    signalSources: [any PetSignalSource],
    notificationCapability: NotificationCapability = .unsupported(.sourceApplicationUnavailable),
    avatarRepository: AvatarRepository? = nil,
    todoStore: TodoStore? = nil,
    usageStore: UsageStatsStore? = nil,
    poseProvider: (any AIPoseProvider)? = nil,
    eyeLocator: (any EyeBandLocating)? = nil
  ) {
    self.defaults = defaults
    self.quietMode = defaults.bool(forKey: Keys.quietMode)
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    let storedScale = defaults.double(forKey: Keys.petScale)
    self.petScale = storedScale > 0 ? storedScale : 1.0
    self.notificationCapability = notificationCapability
    self.signalSources = signalSources
    self.avatarRepository = avatarRepository
    self.todoStore = todoStore
    self.usageStore = usageStore
    self.poseProvider = poseProvider
    self.eyeLocator = eyeLocator
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
    tasks.append(Task { [weak self] in await self?.loadTodoItems() })
    tasks.append(Task { [weak self] in await self?.loadUsageStats() })
    diagnostics.record(category: "app", message: "started")
    AppLog.app.info("PetDesk started")
  }

  func stop() {
    for task in tasks {
      task.cancel()
    }
    tasks.removeAll()
    flushUsageStats()
    diagnostics.record(category: "app", message: "stopped")
  }

  func startFocus() {
    quickActionsVisible = false
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
      avatarError = "头像存储不可用。"
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
      avatarError = "图片导入失败。"
      diagnostics.record(category: "avatar", message: "avatar-import-failed")
      AppLog.avatar.error("Avatar import failed")
    }
  }

  func loadSourceForEdit(from url: URL) async {
    guard let avatarRepository else {
      avatarError = "头像存储不可用。"
      return
    }
    do {
      let image = try await avatarRepository.loadSourceImage(from: url)
      avatarSourceImage = image
      avatarError = nil
    } catch let error as AvatarImportError {
      avatarError = Self.avatarMessage(for: error)
    } catch {
      avatarError = "图片加载失败。"
    }
  }

  func saveCroppedAvatar(_ image: CGImage) async {
    guard let avatarRepository else {
      avatarError = "头像存储不可用。"
      return
    }
    do {
      let storedURL = try await avatarRepository.saveAvatar(image)
      avatarImage = AvatarImageLoader.load(from: storedURL)
      avatarSpritesheet = await generateSpritesheet(from: image)
      avatarSourceImage = nil
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-cropped")
      AppLog.avatar.info("Avatar cropped and saved")
    } catch {
      avatarError = "裁切后的图片保存失败。"
      diagnostics.record(category: "avatar", message: "avatar-crop-failed")
    }
  }

  func resetAvatar() async {
    guard let avatarRepository else { return }
    do {
      try await avatarRepository.resetAvatar()
      try await avatarRepository.deleteSpritesheet()
      avatarImage = nil
      avatarSpritesheet = nil
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-reset")
    } catch {
      avatarError = "头像重置失败。"
    }
  }

  // MARK: Todo

  func addTodoItem(_ title: String) {
    let item = TodoItem(title: title)
    todoItems.append(item)
    persistTodo()
  }

  func toggleTodoItem(id: UUID) {
    guard let index = todoItems.firstIndex(where: { $0.id == id }) else { return }
    todoItems[index].isCompleted.toggle()
    persistTodo()
  }

  func deleteTodoItem(id: UUID) {
    todoItems.removeAll { $0.id == id }
    persistTodo()
  }

  /// Cancel any active focus then feed low CPU to nudge the pet toward
  /// 喝茶 (drinkingTea).
  func slackOff() {
    quickActionsVisible = false
    if focusSession.phase == .running || focusSession.phase == .pausedForIdle {
      cancelFocus()
    }
    for _ in 0..<10 {
      handle(.systemMetrics(SystemMetrics(cpuLoad: 0.12, thermalLevel: .nominal)))
    }
  }

  /// Put the pet to sleep (Zzz) for 15 seconds.  Real idle events are
  /// intercepted while the forced sleep is active so the effect is not
  /// immediately overwritten by the monitor's next reading.
  func relax() {
    quickActionsVisible = false
    if focusSession.phase == .running || focusSession.phase == .pausedForIdle {
      cancelFocus()
    }
    // Send the sleep trigger BEFORE arming the interception, otherwise
    // handle() drops it as a "real idle" event while forcedSleepRemaining
    // is already non-zero and the pet never enters sleeping.
    handle(.userIdleChanged(.seconds(301)))
    forcedSleepRemaining = .seconds(15)
  }

  func injectNotification(_ source: NotificationSource) {
    handle(.notificationPulse(source))
  }

  func updatePetWindowFrame(_ frame: CGRect) {
    petWindowFrame = frame
  }

  /// 窗口控制器在显示/隐藏/遮挡变化时更新动画暂停状态。
  func updatePetAnimationPaused(_ paused: Bool) {
    isPetAnimationPaused = paused
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
    if forcedSleepRemaining > .zero {
      switch event {
      case .userIdleChanged:
        return  // keep forced sleep state; ignore the monitor's real reading
      case .tick(let duration):
        forcedSleepRemaining -= duration
        if forcedSleepRemaining <= .zero {
          forcedSleepRemaining = .zero
          return  // drop the tick that ended the forced sleep
        }
      default:
        break
      }
    }
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

    accumulateUsageStats()
  }

  /// 按宠物当前状态累计 专注/摸鱼/休息 时长，每 30 秒批量写盘。
  private func accumulateUsageStats() {
    switch snapshot.baseState {
    case .focusing: dayAccumulator.focusSeconds += 1
    case .drinkingTea: dayAccumulator.teaSeconds += 1
    case .sleeping: dayAccumulator.sleepSeconds += 1
    default: break
    }

    // 跨天检测：日期变化时归档旧数据并开启新一天。
    let todayKey = DayStats.todayKey()
    if todayKey != currentDayKey {
      flushUsageStats()
      currentDayKey = todayKey
      dayAccumulator = DayStats(date: todayKey)
    }

    secondsSinceStatsFlush += 1
    if secondsSinceStatsFlush >= 30 {
      flushUsageStats()
      secondsSinceStatsFlush = 0
    }
  }

  private func loadUsageStats() async {
    guard let usageStore else { return }
    let days = await usageStore.loadAll()
    usageStatsByDay = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
    // 恢复今天已存的累计值，避免重启后丢失。
    if let existing = usageStatsByDay[currentDayKey] {
      dayAccumulator = existing
    }
  }

  private func flushUsageStats() {
    guard let usageStore else { return }
    let day = dayAccumulator
    let key = currentDayKey
    Task {
      try? await usageStore.upsert(day)
      await MainActor.run {
        usageStatsByDay[key] = day
      }
    }
  }

  private func loadTodoItems() async {
    guard let todoStore else { return }
    todoItems = await todoStore.load()
  }

  private func persistTodo() {
    guard let todoStore else { return }
    let snapshot = todoItems
    Task { try? await todoStore.save(snapshot) }
  }

  private func loadStoredAvatar() async {
    guard let avatarRepository else { return }
    let url = await avatarRepository.avatarURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    avatarImage = AvatarImageLoader.load(from: url)
    avatarSpritesheet = await avatarRepository.loadSpritesheet()
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

  /// 用裁切后的头像生成精灵图并保存；失败时保留旧精灵图（静默降级）。
  /// 优先尝试 AI provider（未配置或失败时回退本地程序化生成器）。
  private func generateSpritesheet(from image: CGImage) async -> CGImage? {
    guard avatarRepository != nil else { return nil }
    if let provider = poseProvider {
      if let aiSheet = try? await provider.generateSpritesheet(from: image) {
        return await saveSpritesheet(aiSheet)
      }
      diagnostics.record(category: "avatar", message: "ai-pose-fallback")
    }
    let eyeBand = eyeLocator?.eyeBand(in: image)
    guard let sheet = SpriteSheetGenerator.generate(from: image, eyeBandInSource: eyeBand) else {
      return nil
    }
    return await saveSpritesheet(sheet)
  }

  private func saveSpritesheet(_ sheet: CGImage) async -> CGImage? {
    guard let avatarRepository else { return nil }
    do {
      try await avatarRepository.saveSpritesheet(sheet)
      return sheet
    } catch {
      AppLog.avatar.error("Spritesheet save failed")
      return nil
    }
  }

  private static func avatarMessage(for error: AvatarImportError) -> String {
    switch error {
    case .fileTooLarge: "请选择小于 20 MB 的图片。"
    case .unsupportedType: "请选择 PNG、JPEG 或 HEIC 格式的图片。"
    case .unreadableImage: "无法读取所选文件。"
    case .encodingFailed: "图片保存失败。"
    }
  }
}
