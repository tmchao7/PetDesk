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
  @Published private(set) var focusSession: FocusSession
  @Published var quickActionsVisible = false
  @Published private(set) var petWindowFrame: CGRect?
  @Published private(set) var avatarError: String?
  @Published private(set) var avatarSourceImage: CGImage?
  /// 已设置的逐行自定义姿势（专注/摸鱼/休息等），用于 UI 显示状态。
  @Published private(set) var customPoseRows: Set<AnimationRow> = []
  /// 自定义姿势的缩略图（每帧一张，供设置界面即时预览；第一帧为主预览）。
  @Published private(set) var customPoseImages: [AnimationRow: [NSImage]] = [:]
  @Published var avatarDisplayMode: AvatarDisplayMode {
    didSet { defaults.set(avatarDisplayMode.rawValue, forKey: Keys.avatarDisplayMode) }
  }
  /// 状态时长提醒阈值（分钟）：专注/摸鱼/放松各自可调。
  @Published var focusDurationMinutes: Int {
    didSet { defaults.set(focusDurationMinutes, forKey: Keys.focusDurationMinutes) }
  }
  @Published var slackDurationMinutes: Int {
    didSet { defaults.set(slackDurationMinutes, forKey: Keys.slackDurationMinutes) }
  }
  @Published var relaxDurationMinutes: Int {
    didSet { defaults.set(relaxDurationMinutes, forKey: Keys.relaxDurationMinutes) }
  }
  /// 状态时长提醒文案模板（支持 {minutes} 占位符），三种状态各自可自定义。
  @Published var focusReminderMessage: String {
    didSet { defaults.set(focusReminderMessage, forKey: Keys.focusReminderMessage) }
  }
  @Published var slackReminderMessage: String {
    didSet { defaults.set(slackReminderMessage, forKey: Keys.slackReminderMessage) }
  }
  @Published var relaxReminderMessage: String {
    didSet { defaults.set(relaxReminderMessage, forKey: Keys.relaxReminderMessage) }
  }
  /// 单次提醒气泡的显示时长（秒），用户可在设置里调整。
  @Published var reminderDisplaySeconds: Int {
    didSet { defaults.set(reminderDisplaySeconds, forKey: Keys.reminderDisplaySeconds) }
  }
  @Published var petScale: Double {
    didSet { defaults.set(petScale, forKey: Keys.petScale) }
  }
  /// 宠物窗口不可见或被遮挡时为 true，视图据此暂停帧动画与 Timeline 驱动。
  @Published private(set) var isPetAnimationPaused = true
  /// 最新 CPU 读数（0~1）。故意不做 @Published：动画速度读取用，
  /// 不触发视图重算（与 snapshot 发布门控保持一致的性能约束）。
  private(set) var latestCPU: Double = 0
  /// 辅助窗口（设置/统计/待办/诊断）可见计数：任一可见时保持 .regular
  /// （Dock 图标 + Cmd-Tab），全部关闭才回 .accessory——避免多窗口同时
  /// 打开时关掉一个就把应用降级导致其余窗口失焦/Dock 图标消失。
  private var auxiliaryWindowCount = 0

  /// 辅助窗口出现：切 .regular 并激活（幂等），计数 +1。
  func auxiliaryWindowDidAppear() {
    auxiliaryWindowCount += 1
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// 辅助窗口关闭：计数 -1；归零时回 .accessory。
  func auxiliaryWindowDidDisappear() {
    auxiliaryWindowCount = max(0, auxiliaryWindowCount - 1)
    if auxiliaryWindowCount == 0 {
      NSApp.setActivationPolicy(.accessory)
    }
  }

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

  /// 气泡待办列表：全部未完成项（气泡内滚动查看，不再截断前 5 条）。
  var incompleteTodoItems: [TodoItem] {
    todoItems.filter { !$0.isCompleted }
  }

  /// 某行动画行的自定义帧数（0 = 未设置；1 = 静态单帧；>1 = 多帧动画）。
  func multiFrameCount(for row: AnimationRow) -> Int {
    customPoseCells[row]?.count ?? 0
  }

  private enum Keys {
    static let avatarDisplayMode = "avatarDisplayMode"
    static let focusDurationMinutes = "focusDurationMinutes"
    static let slackDurationMinutes = "slackDurationMinutes"
    static let relaxDurationMinutes = "relaxDurationMinutes"
    static let focusReminderMessage = "focusReminderMessage"
    static let slackReminderMessage = "slackReminderMessage"
    static let relaxReminderMessage = "relaxReminderMessage"
    static let reminderDisplaySeconds = "reminderDisplaySeconds"
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
  /// 每行动画行的自定义姿势帧（多帧动画：一行为多张动作帧）。
  /// 单帧行存 [cell]；未设置的行用头像基准单元。
  private var customPoseCells: [AnimationRow: [CGImage]] = [:]
  private let signalSources: [any PetSignalSource]
  private var machine = PetStateMachine()
  private var activityReminder = ActivityReminderAccumulator()
  private var latestIdle: Duration = .zero
  /// 用户手动选择的摸鱼/放松状态：锁定期间忽略 CPU/idle 统计事件，
  /// 直到用户再点 专注/摸鱼/放松（点击什么就是什么，不自动切回）。
  private var manualState: BasePetState?
  /// 用户当前选择的状态（专注/摸鱼/放松），用于“已连续 xx 分钟”气泡提醒。
  private var pinnedState: BasePetState?
  private var stateDuration: Duration = .zero
  private var lastReminderCycle = 0
  private var reminderBubbleRemaining: Duration = .zero
  /// 当前正在显示的提醒文案；状态机每秒 reduce 会覆盖 snapshot.bubble，
  /// 需要用它把提醒气泡重新挂回去，直到显示时长结束。
  private var activeReminderText: String?
  private var currentDayKey = DayStats.todayKey()
  private var dayAccumulator = DayStats(date: DayStats.todayKey())
  private var secondsSinceStatsFlush = 0
  private var tasks: [Task<Void, Never>] = []
  private var reminderWasDue = false
  /// 持久化写盘串行链：多次触发（todo 快速勾选、30s 批量 + stop 竞态）按
  /// 触发顺序依次落盘，避免乱序覆盖丢数据。
  private var pendingWrite: Task<Void, Never>?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    self.focusDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.focusDurationMinutes), fallback: 25)
    self.slackDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.slackDurationMinutes), fallback: 10)
    self.relaxDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.relaxDurationMinutes), fallback: 10)
    self.focusReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.focusReminderMessage), fallback: Self.defaultFocusReminder)
    self.slackReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.slackReminderMessage), fallback: Self.defaultSlackReminder)
    self.relaxReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.relaxReminderMessage), fallback: Self.defaultRelaxReminder)
    self.reminderDisplaySeconds = Self.displaySeconds(
      defaults.integer(forKey: Keys.reminderDisplaySeconds))
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
    self.focusSession = FocusSession()
  }

  init(
    defaults: UserDefaults = .standard,
    signalSources: [any PetSignalSource],
    notificationCapability: NotificationCapability = .unsupported(.sourceApplicationUnavailable),
    avatarRepository: AvatarRepository? = nil,
    todoStore: TodoStore? = nil,
    usageStore: UsageStatsStore? = nil,
    poseProvider: (any AIPoseProvider)? = nil,
    eyeLocator: (any EyeBandLocating)? = nil,
    focusSession: FocusSession = FocusSession()
  ) {
    self.defaults = defaults
    self.avatarDisplayMode =
      defaults.string(forKey: Keys.avatarDisplayMode)
      .flatMap(AvatarDisplayMode.init) ?? .circle
    self.focusDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.focusDurationMinutes), fallback: 25)
    self.slackDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.slackDurationMinutes), fallback: 10)
    self.relaxDurationMinutes = Self.durationMinutes(
      defaults.integer(forKey: Keys.relaxDurationMinutes), fallback: 10)
    self.focusReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.focusReminderMessage), fallback: Self.defaultFocusReminder)
    self.slackReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.slackReminderMessage), fallback: Self.defaultSlackReminder)
    self.relaxReminderMessage = Self.reminderMessage(
      defaults.string(forKey: Keys.relaxReminderMessage), fallback: Self.defaultRelaxReminder)
    self.reminderDisplaySeconds = Self.displaySeconds(
      defaults.integer(forKey: Keys.reminderDisplaySeconds))
    let storedScale = defaults.double(forKey: Keys.petScale)
    self.petScale = storedScale > 0 ? storedScale : 1.0
    self.notificationCapability = notificationCapability
    self.signalSources = signalSources
    self.avatarRepository = avatarRepository
    self.todoStore = todoStore
    self.usageStore = usageStore
    self.poseProvider = poseProvider
    self.eyeLocator = eyeLocator
    self.focusSession = focusSession
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
    manualState = .focusing
    pinnedState = .focusing
    resetStateDuration()
    // 状态切换 = 新会话：重置活动提醒累计，避免已触发未确认的提醒
    // （reminderWasDue/isDue 无自清）在本次进程内永久卡死不再触发。
    reminderWasDue = false
    activityReminder.acknowledgeBreak()
    focusSession.start()
    handle(.focusCommand(.start))
    diagnostics.record(category: "focus", message: "session-started")
    AppLog.focus.info("Focus session started")
  }

  func cancelFocus() {
    // 显式取消专注 = 解除钉住，恢复真实 CPU/空闲驱动。钉住期间
    // userIdleChanged 被拦截、状态机内的 idle 停留旧值，这里把最近一次
    // 真实 idle 同步回去，避免取消后按旧 idle 直接睡回放松。
    manualState = nil
    // 与 startFocus/slackOff/relax 一致：取消会话也重置活动提醒，
    // 防止直接调用本方法（未来菜单/快捷键等入口）让提醒永久卡死。
    reminderWasDue = false
    activityReminder.acknowledgeBreak()
    focusSession.cancel()
    handle(.userIdleChanged(latestIdle))
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

  /// 取消头像编辑：释放源图内存并清掉上次导入的错误提示（不落盘、不改头像）。
  func cancelAvatarEdit() {
    avatarSourceImage = nil
    avatarError = nil
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
      // 清掉上次导入的残留源图，避免编辑器弹旧图（可能误确认覆盖当前头像）。
      avatarSourceImage = nil
    } catch {
      avatarError = "图片加载失败。"
      avatarSourceImage = nil
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
      customPoseImages = [:]
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
      customPoseImages = [:]
      avatarError = nil
      diagnostics.record(category: "avatar", message: "avatar-reset")
    } catch {
      avatarError = "头像重置失败。"
    }
  }

  /// 导入一个动画行的姿势帧（专注可多帧：1~8 张动作帧；摸鱼/休息单帧）。
  /// 多帧行的帧将按导入顺序循环播放，速度随 CPU 占用率变化。
  /// - Returns: 失败时的用户可见错误信息；成功返回 nil。
  @discardableResult
  func importPose(row: AnimationRow, from urls: [URL]) async -> String? {
    guard avatarBaseCGImage != nil else {
      let message = "请先设置头像，再导入姿势图。"
      AppLog.avatar.error("Pose import skipped: no avatar base")
      return message
    }
    guard !urls.isEmpty else {
      return "未选择图片。"
    }
    guard urls.count <= SpriteSheetSpec.columns else {
      return "一次最多导入 \(SpriteSheetSpec.columns) 帧。"
    }
    do {
      // 按文件名排序确定播放顺序（fileImporter 多选返回顺序不可靠；
      // 用户按 focus-01…08 命名即期望顺序）。用 Finder 风格数字感知比较，
      // 避免 "专注2" 排在 "专注10" 之后这类字符串排序陷阱。
      let orderedURLs = urls.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
          == .orderedAscending
      }
      var cells: [CGImage] = []
      for url in orderedURLs {
        cells.append(try PoseCellProcessor.loadCell(from: url))
      }
      customPoseCells[row] = cells
      customPoseRows = Set(customPoseCells.keys)
      customPoseImages[row] = cells.map {
        NSImage(cgImage: $0, size: NSSize(width: 48, height: 52))
      }
      if let message = await reassembleSpritesheet() {
        AppLog.avatar.error("Pose import reassembly failed: \(message, privacy: .public)")
        return message
      }
      diagnostics.record(category: "avatar", message: "pose-imported")
      AppLog.avatar.info(
        "Pose imported \(cells.count, privacy: .public) frame(s) for row \(row.rawValue, privacy: .public)"
      )
      return nil
    } catch let error as PoseImageImportError {
      let message = Self.poseMessage(for: error)
      AppLog.avatar.error("Pose image rejected: \(message, privacy: .public)")
      return message
    } catch {
      let message = "姿势图导入失败。"
      AppLog.avatar.error("Pose import failed: \(String(describing: error), privacy: .public)")
      return message
    }
  }

  /// 清除某行的自定义姿势，回退到头像基准形象。
  @discardableResult
  func clearPose(row: AnimationRow) async -> String? {
    customPoseCells.removeValue(forKey: row)
    customPoseRows = Set(customPoseCells.keys)
    customPoseImages.removeValue(forKey: row)
    guard avatarBaseCGImage != nil else { return nil }
    if let message = await reassembleSpritesheet() {
      return message
    }
    diagnostics.record(category: "avatar", message: "pose-cleared")
    return nil
  }

  /// 用头像基准单元 + 自定义姿势帧重拼 8×8 精灵图并保存。
  /// 多帧行按帧序填入列 0..<N，剩余列用基准单元补位；单帧行走程序化微变换。
  private func reassembleSpritesheet() async -> String? {
    guard
      let avatarRepository,
      let avatarBaseCGImage,
      let avatarCell = SpriteSheetGenerator.baseCell(from: avatarBaseCGImage)
    else {
      return "请先设置头像，再导入姿势图。"
    }
    var rowFrames: [AnimationRow: [CGImage]] = [:]
    for row in AnimationRow.allCases {
      rowFrames[row] = customPoseCells[row] ?? [avatarCell]
    }
    guard
      let sheet = SpriteSheetGenerator.generate(
        fromRowFrames: rowFrames, fallbackCell: avatarCell
      )
    else {
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
    manualState = nil
    pinnedState = .drinkingTea
    resetStateDuration()
    reminderWasDue = false
    activityReminder.acknowledgeBreak()
    if focusSession.phase == .running || focusSession.phase == .pausedForIdle {
      cancelFocus()
    }
    handle(.userIdleChanged(.zero))
    for _ in 0..<10 {
      handle(.systemMetrics(SystemMetrics(cpuLoad: 0.12, thermalLevel: .nominal)))
    }
    manualState = .drinkingTea
  }

  /// Put the pet to sleep (Zzz) and keep it sleeping until the user picks
  /// another state — real idle/CPU readings no longer switch it back.
  func relax() {
    quickActionsVisible = false
    manualState = nil
    pinnedState = .sleeping
    resetStateDuration()
    reminderWasDue = false
    activityReminder.acknowledgeBreak()
    if focusSession.phase == .running || focusSession.phase == .pausedForIdle {
      cancelFocus()
    }
    handle(.userIdleChanged(.seconds(301)))
    manualState = .sleeping
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
    manualState = nil
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
    if manualState != nil {
      switch event {
      case .systemMetrics, .userIdleChanged:
        return  // 手动状态锁定：忽略统计事件，保持用户选择的状态
      default:
        break
      }
    }
    var reduced = machine.reduce(event, elapsed: eventElapsed(event))
    latestCPU = reduced.averageCPU
    // 专注钉住：会话完成/取消后状态机 focusActive 解除会回到 CPU/空闲驱动
    // （摸鱼/放松），这里在显示层强制保持专注，直到用户手动切换——与
    // 摸鱼/放松的 manualState 拦截对称（点的是什么状态就是什么状态）。
    if manualState == .focusing {
      reduced.baseState = .focusing
      // 钉住期间系统事件被拦截、状态机 thermal 停在旧值；这里统一清空效果
      // 覆盖（含高温 smoke）——设计如此：专注形象不带特效叠加。
      reduced.effects = []
    }
    // 发布门控：CPU 读数每秒都在变，但宠物外观（状态/特效/气泡）不变时
    // 跳过发布，避免每秒无效化悬浮窗整树重绘。averageCPU 只进诊断窗口，
    // 允许滞后到下一次外观变化时一并刷新。
    if !reduced.displayEquals(snapshot) { snapshot = reduced }
    reapplyReminderBubbleIfNeeded()
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
    if activityReminder.isDue, !reminderWasDue {
      reminderWasDue = true
      handle(.focusCommand(.showActivityReminder))
    }

    advanceStateDurationReminder(by: .seconds(1))
    accumulateUsageStats()
  }

  /// 状态连续时长提醒：到达设定时长（如每 25 分钟）弹一次气泡，
  /// 按设置的单次显示时长（默认 10 秒）自动消失；仅提醒，不切换状态。
  /// 点击 专注/摸鱼/放松 时重新计时。
  func advanceStateDurationReminder(by duration: Duration) {
    // 先处理既有提醒的自动消失（避免本次推进刚触发的提醒被立即清掉）。
    if reminderBubbleRemaining > .zero {
      reminderBubbleRemaining -= min(reminderBubbleRemaining, duration)
      if reminderBubbleRemaining <= .zero {
        reminderBubbleRemaining = .zero
        activeReminderText = nil
        if case .stateDurationReminder? = snapshot.bubble {
          snapshot.bubble = nil
        }
      } else {
        reapplyReminderBubbleIfNeeded()
      }
    }

    if let pinnedState, snapshot.baseState == pinnedState {
      stateDuration += duration
      let threshold = durationMinutes(for: pinnedState)
      let minutes = Int(stateDuration / .seconds(60))
      if threshold > 0, minutes >= threshold, minutes % threshold == 0,
        minutes != lastReminderCycle
      {
        lastReminderCycle = minutes
        let text = reminderText(for: pinnedState, minutes: minutes)
        activeReminderText = text
        snapshot.bubble = .stateDurationReminder(text)
        reminderBubbleRemaining = .seconds(max(1, reminderDisplaySeconds))
      }
    } else if stateDuration > .zero {
      // 状态离开计时范围（如专注会话结束）时清零，下次点击重新计时。
      stateDuration = .zero
      lastReminderCycle = 0
    }
  }

  /// 状态机每次 reduce 都会用它的快照覆盖 bubble；提醒显示期间把它挂回去。
  /// 不覆盖其他类型的气泡（如专注完成、活动提醒）。
  private func reapplyReminderBubbleIfNeeded() {
    guard reminderBubbleRemaining > .zero, let text = activeReminderText else { return }
    if snapshot.bubble == nil || snapshot.bubble == .stateDurationReminder(text) {
      snapshot.bubble = .stateDurationReminder(text)
    }
  }

  private func durationMinutes(for state: BasePetState) -> Int {
    switch state {
    case .focusing: max(1, focusDurationMinutes)
    case .drinkingTea: max(1, slackDurationMinutes)
    case .sleeping: max(1, relaxDurationMinutes)
    default: 0
    }
  }

  /// 渲染提醒文案：把模板中的 {minutes} / {m} 替换为实际分钟数。
  /// 设置界面也用同一方法做实时预览。
  func reminderText(for state: BasePetState, minutes: Int) -> String {
    let template: String
    switch state {
    case .focusing:
      template = Self.reminderMessage(focusReminderMessage, fallback: Self.defaultFocusReminder)
    case .drinkingTea:
      template = Self.reminderMessage(slackReminderMessage, fallback: Self.defaultSlackReminder)
    case .sleeping:
      template = Self.reminderMessage(relaxReminderMessage, fallback: Self.defaultRelaxReminder)
    default:
      template = "你已连续 {minutes} 分钟"
    }
    return
      template
      .replacingOccurrences(of: "{minutes}", with: "\(minutes)")
      .replacingOccurrences(of: "{m}", with: "\(minutes)")
  }

  private func resetStateDuration() {
    stateDuration = .zero
    lastReminderCycle = 0
    reminderBubbleRemaining = .zero
    activeReminderText = nil
    if case .stateDurationReminder? = snapshot.bubble {
      snapshot.bubble = nil
    }
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
    // 恢复今天已存的累计值。启动瞬间 tick 可能已累计几秒，
    // 与磁盘值合并而不是覆盖，避免丢秒。
    if let existing = usageStatsByDay[currentDayKey] {
      dayAccumulator.focusSeconds += existing.focusSeconds
      dayAccumulator.teaSeconds += existing.teaSeconds
      dayAccumulator.sleepSeconds += existing.sleepSeconds
    }
  }

  private func flushUsageStats() {
    guard let usageStore else { return }
    let day = dayAccumulator
    let key = currentDayKey
    let previous = pendingWrite
    pendingWrite = Task {
      _ = await previous?.value
      do {
        try await usageStore.upsert(day)
        await MainActor.run {
          usageStatsByDay[key] = day
        }
      } catch {
        await MainActor.run {
          diagnostics.record(category: "stats", message: "usage-stats-write-failed")
          AppLog.app.error("Usage stats write failed: \(String(describing: error))")
        }
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
    let previous = pendingWrite
    pendingWrite = Task {
      _ = await previous?.value
      do {
        try await todoStore.save(snapshot)
      } catch {
        await MainActor.run {
          diagnostics.record(category: "todo", message: "todo-save-failed")
          AppLog.app.error("Todo save failed: \(String(describing: error))")
        }
      }
    }
  }

  private func loadStoredAvatar() async {
    guard let avatarRepository else { return }
    let url = await avatarRepository.avatarURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    // 竞态防护：加载期间用户可能已完成导入（avatarImage 已被设置），
    // 此时不再用磁盘旧图覆盖内存显示（磁盘本身已是新图，重启即正确）。
    guard avatarImage == nil else { return }
    avatarImage = AvatarImageLoader.load(from: url)
    avatarBaseCGImage = await avatarRepository.loadAvatarCGImage()
    avatarSpritesheet = await avatarRepository.loadSpritesheet()
    syncCustomPoseStateFromSpritesheet()
  }

  /// 从已加载的精灵图反解自定义姿势行：把与头像基准单元像素不同的行恢复为
  /// 自定义行（cells + 缩略图），保证重启后 Settings 仍显示“更换/清除”，
  /// 且清除某行时不会误伤其余已导入行。
  private func syncCustomPoseStateFromSpritesheet() {
    customPoseCells.removeAll()
    customPoseRows = []
    customPoseImages = [:]
    guard
      let avatarBaseCGImage,
      let baseCell = SpriteSheetGenerator.baseCell(from: avatarBaseCGImage),
      let avatarSpritesheet
    else { return }
    for row in [AnimationRow.working, .drinking, .sleeping] {
      // 从列 0 起逐列收集自定义帧：遇到基准单元填充（多帧行补位或单帧
      // 行第 1 列起）即停止。多帧行恢复全部 N 帧，单帧行恢复 1 帧。
      var frames: [CGImage] = []
      for column in 0..<SpriteSheetSpec.columns {
        let frameRect = CGRect(
          x: CGFloat(column) * SpriteSheetSpec.frameWidth,
          y: CGFloat(row.rawValue) * SpriteSheetSpec.frameHeight,
          width: SpriteSheetSpec.frameWidth,
          height: SpriteSheetSpec.frameHeight
        )
        guard let frame = avatarSpritesheet.cropping(to: frameRect) else { break }
        if Self.cgImagesEqual(frame, baseCell) { break }
        frames.append(frame)
      }
      guard !frames.isEmpty else { continue }
      customPoseCells[row] = frames
      customPoseRows.insert(row)
      customPoseImages[row] = frames.map {
        NSImage(cgImage: $0, size: NSSize(width: 48, height: 52))
      }
    }
  }

  /// 逐像素比较两张同尺寸图像（容差 4/255，容忍 PNG 往返与色彩管理的舍入误差）。
  private static func cgImagesEqual(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
    guard lhs.width == rhs.width, lhs.height == rhs.height else { return false }
    let width = lhs.width
    let height = lhs.height
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    func renderedBytes(_ image: CGImage) -> Data? {
      guard
        let context = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: bitmapInfo.rawValue
        ),
        let data = context.data
      else { return nil }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return Data(bytes: data, count: height * context.bytesPerRow)
    }

    guard let lhsBytes = renderedBytes(lhs), let rhsBytes = renderedBytes(rhs) else {
      return false
    }
    var differences = 0
    for index in 0..<lhsBytes.count {
      let delta = abs(Int(lhsBytes[index]) - Int(rhsBytes[index]))
      if delta > 4 {
        differences += 1
        if differences > max(16, width * height / 200) {
          return false
        }
      }
    }
    return true
  }

  /// 读取时长设置：只接受 1...180 分钟，非法值回退默认。
  private static func durationMinutes(_ stored: Int, fallback: Int) -> Int {
    (1...180).contains(stored) ? stored : fallback
  }

  /// 单次提醒显示时长（秒）：只接受 1...120 秒，非法值回退默认 10 秒。
  private static func displaySeconds(_ stored: Int) -> Int {
    (1...120).contains(stored) ? stored : 10
  }

  private static let defaultFocusReminder = "你已连续专注 {minutes} 分钟"
  private static let defaultSlackReminder = "你已连续摸鱼 {minutes} 分钟"
  private static let defaultRelaxReminder = "你已连续放松 {minutes} 分钟"

  /// 读取提醒文案模板：空白时回退默认模板。
  private static func reminderMessage(_ stored: String?, fallback: String) -> String {
    guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return fallback
    }
    return stored
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

  private static func poseMessage(for error: PoseImageImportError) -> String {
    switch error {
    case .unreadableImage: "无法读取所选姿势图。"
    case .unsupportedType: "请选择 PNG 或 WebP 格式的姿势图。"
    case .emptySubject: "姿势图中没有识别到主体（请确认人物清晰、背景为纯色或透明）。"
    }
  }
}
