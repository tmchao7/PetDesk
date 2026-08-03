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
  /// 已设置的逐行自定义姿势（专注/摸鱼/休息等），用于 UI 显示状态。
  @Published private(set) var customPoseRows: Set<AnimationRow> = []
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
  /// 头像的 CGImage 基准（逐行姿势混合组装用；重启后从存储重新加载）。
  private var avatarBaseCGImage: CGImage?
  /// 每行动画行的自定义姿势单元；未设置的行动画用头像基准单元。
  private var customPoseCells: [AnimationRow: CGImage] = [:]
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
      avatarBaseCGImage = image
      customPoseCells.removeAll()
      customPoseRows = []
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
      avatarBaseCGImage = nil
      customPoseCells.removeAll()
      customPoseRows = []
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-reset")
    } catch {
      avatarError = "头像重置失败。"
    }
  }

  /// 导入用户自备的整张精灵图（在线 AI 生成后上传）。
  /// - Returns: 失败时的用户可见错误信息；成功返回 nil。
  @discardableResult
  func importSpritesheet(from url: URL) async -> String? {
    guard let avatarRepository else {
      let message = "头像存储不可用。"
      avatarError = message
      return message
    }
    do {
      let sheet = try await avatarRepository.importSpritesheet(from: url)
      avatarSpritesheet = sheet
      avatarError = nil
      diagnostics.record(category: "avatar", message: "spritesheet-imported")
      return nil
    } catch let error as SpritesheetImportError {
      let message = Self.spritesheetMessage(for: error)
      avatarError = message
      diagnostics.record(category: "avatar", message: "spritesheet-import-failed")
      return message
    } catch {
      let message = "精灵图导入失败。"
      avatarError = message
      diagnostics.record(category: "avatar", message: "spritesheet-import-failed")
      return message
    }
  }

  /// 导入单个动画行的姿势图（如专注/摸鱼/休息），随后重新组装精灵图。
  /// - Returns: 失败时的用户可见错误信息；成功返回 nil。
  @discardableResult
  func importPose(row: AnimationRow, from url: URL) async -> String? {
    guard avatarBaseCGImage != nil else {
      let message = "请先设置头像，再导入姿势图。"
      return message
    }
    do {
      let cell = try PoseCellProcessor.loadCell(from: url)
      customPoseCells[row] = cell
      customPoseRows = Set(customPoseCells.keys)
      if let message = await reassembleSpritesheet() {
        return message
      }
      diagnostics.record(category: "avatar", message: "pose-imported")
      return nil
    } catch let error as PoseImageImportError {
      return Self.poseMessage(for: error)
    } catch {
      return "姿势图导入失败。"
    }
  }

  /// 清除某行的自定义姿势，回退到头像基准形象。
  @discardableResult
  func clearPose(row: AnimationRow) async -> String? {
    customPoseCells.removeValue(forKey: row)
    customPoseRows = Set(customPoseCells.keys)
    guard avatarBaseCGImage != nil else { return nil }
    if let message = await reassembleSpritesheet() {
      return message
    }
    diagnostics.record(category: "avatar", message: "pose-cleared")
    return nil
  }

  /// 用头像基准单元 + 自定义姿势单元重拼 8×8 精灵图并保存。
  private func reassembleSpritesheet() async -> String? {
    guard
      let avatarRepository,
      let avatarBaseCGImage,
      let avatarCell = SpriteSheetGenerator.baseCell(from: avatarBaseCGImage)
    else {
      return "请先设置头像，再导入姿势图。"
    }
    var rowCells: [AnimationRow: CGImage] = [:]
    for row in AnimationRow.allCases {
      rowCells[row] = customPoseCells[row] ?? avatarCell
    }
    guard let sheet = SpriteSheetGenerator.generate(fromRowCells: rowCells) else {
      return "精灵图组装失败。"
    }
    do {
      try await avatarRepository.saveSpritesheet(sheet)
      avatarSpritesheet = sheet
      return nil
    } catch {
      return "精灵图保存失败。"
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
    avatarBaseCGImage = await avatarRepository.loadAvatarCGImage()
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

  private static func spritesheetMessage(for error: SpritesheetImportError) -> String {
    switch error {
    case .unreadableImage: "无法读取所选文件。"
    case .unsupportedType: "请选择 PNG 或 WebP 格式的精灵图。"
    case .invalidDimensions:
      "尺寸不符合：需要 1536×1664，或宽高都能被 8 整除的 8×8 网格（如 1024×1024、1728×2304）。"
    case .invalidGrid:
      "无法识别为整齐的 8×8 动作网格（格子边界有内容或角色跨格）。请生成 1:1 方形、每格独立姿势、纯色背景的图集，或改用单张头像自动生成动画。"
    case .missingAlpha:
      "图片没有透明背景且四角颜色不一致，无法自动抠底。请用透明 PNG，或保证背景为纯色（四角同色）。"
    case .sparseCell(let row, let column):
      "精灵图第 \(row + 1) 行第 \(column + 1) 列几乎没有内容。"
    }
  }

  private static func poseMessage(for error: PoseImageImportError) -> String {
    switch error {
    case .unreadableImage: "无法读取所选姿势图。"
    case .unsupportedType: "请选择 PNG 或 WebP 格式的姿势图。"
    case .emptySubject: "姿势图中没有识别到主体（请确认人物清晰、背景为纯色或透明）。"
    }
  }
}
