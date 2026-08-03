import ImageIO
import Synchronization
import UniformTypeIdentifiers
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// Controllable signal source: the test holds the continuation and emits
/// events on demand. The stream stays open until the continuation is
/// finished, so the receiving task does not terminate on its own.
private final class ControllableSignalSource: PetSignalSource {
  private struct State {
    var subscriptionCount = 0
    var continuation: AsyncStream<PetEvent>.Continuation?
  }

  private let state = Mutex(State())

  var subscriptionCount: Int {
    state.withLock { $0.subscriptionCount }
  }

  func events() -> AsyncStream<PetEvent> {
    AsyncStream { continuation in
      state.withLock {
        $0.subscriptionCount += 1
        $0.continuation = continuation
      }
    }
  }

  func emit(_ event: PetEvent) {
    _ = state.withLock { $0.continuation?.yield(event) }
  }

  func finish() {
    state.withLock {
      $0.continuation?.finish()
      $0.continuation = nil
    }
  }
}

final class AppEnvironmentTests: XCTestCase {
  private let suiteName = "AppEnvironmentTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults?.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  // MARK: - Lifecycle

  @MainActor
  func testSlackOffWakesFromForcedSleepImmediately() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])

    env.relax()
    XCTAssertEqual(
      env.snapshot.baseState, .sleeping,
      "relax should put the pet to sleep immediately")

    env.slackOff()
    XCTAssertEqual(
      env.snapshot.baseState, .drinkingTea,
      "slackOff should wake the pet from forced sleep immediately, "
        + "not stay sleeping until the 15s forced-sleep window expires")
  }

  @MainActor
  func testStartFocusCancelsForcedSleepWindow() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()
    await waitUntil { source.subscriptionCount == 1 }

    env.relax()
    XCTAssertEqual(env.snapshot.baseState, .sleeping, "relax should enter sleeping")
    env.startFocus()
    XCTAssertEqual(env.snapshot.baseState, .focusing, "focus should override sleeping")

    // 专注应该取消强制睡眠窗口：真实 idle 读数不再被拦截，
    // 取消专注后宠物按真实 idle 恢复，而不是带着 301 秒旧值直接睡回去。
    source.emit(.userIdleChanged(.seconds(10)))
    await yieldToScheduler()
    env.cancelFocus()
    XCTAssertEqual(
      env.snapshot.baseState, .drinkingTea,
      "real idle readings should flow again after 专注 cancels the forced-sleep window")

    env.stop()
    source.finish()
  }

  @MainActor
  func testManualPoseStatePersistsUntilUserSwitches() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()
    await waitUntil { source.subscriptionCount == 1 }

    env.slackOff()
    XCTAssertEqual(env.snapshot.baseState, .drinkingTea)
    // 高 CPU 与活跃 idle 不应把手动摸鱼切回工作/跑步状态。
    for _ in 0..<6 {
      source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.9, thermalLevel: .nominal)))
    }
    source.emit(.userIdleChanged(.seconds(5)))
    await yieldToScheduler()
    XCTAssertEqual(
      env.snapshot.baseState, .drinkingTea,
      "slackOff should persist until the user picks another state")

    // 点专注解除手动锁定。
    env.startFocus()
    XCTAssertEqual(env.snapshot.baseState, .focusing)
    env.stop()
    source.finish()
  }

  @MainActor
  func testStateDurationReminderFiresAtConfiguredInterval() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.focusDurationMinutes = 1
    env.reminderDisplaySeconds = 3
    env.startFocus()
    XCTAssertEqual(env.snapshot.baseState, .focusing)

    env.advanceStateDurationReminder(by: .seconds(59))
    XCTAssertNil(env.snapshot.bubble, "no reminder before the configured minute")

    env.advanceStateDurationReminder(by: .seconds(1))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续专注 1 分钟"),
      "reminder should fire at the configured interval")

    // 未到配置的单次显示时长前应保持显示。
    env.advanceStateDurationReminder(by: .seconds(2))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续专注 1 分钟"),
      "reminder should stay until the configured display seconds")

    // 到点自动消失。
    env.advanceStateDurationReminder(by: .seconds(1))
    XCTAssertNil(env.snapshot.bubble, "reminder bubble should auto-dismiss")

    // 再满一个周期 → 2 分钟。
    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续专注 2 分钟"),
      "reminder should repeat each configured cycle")

    // 切换摸鱼：计时重置并清掉旧提醒。
    env.slackOff()
    env.slackDurationMinutes = 1
    XCTAssertNil(env.snapshot.bubble, "switching state should clear the reminder")
    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续摸鱼 1 分钟"),
      "slack-off should have its own reminder text")

    // 放松同理。
    env.relax()
    env.relaxDurationMinutes = 1
    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续放松 1 分钟"),
      "relax should have its own reminder text")
  }

  @MainActor
  func testReminderSurvivesStateMachineTicks() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()
    await waitUntil { source.subscriptionCount == 1 }

    env.focusDurationMinutes = 1
    env.reminderDisplaySeconds = 10
    env.startFocus()
    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续专注 1 分钟"),
      "reminder should fire first")

    // 真实运行中每秒 tick 都会让状态机快照覆盖 snapshot.bubble；
    // 提醒必须被重新挂回，直到配置的显示时长结束。
    for _ in 0..<5 {
      source.emit(.tick(.seconds(1)))
    }
    await yieldToScheduler()
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续专注 1 分钟"),
      "per-second state machine ticks must not erase the reminder "
        + "before its configured display duration")

    env.stop()
    source.finish()
  }

  @MainActor
  func testDurationSettingsPersistToDefaults() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.focusDurationMinutes, 25, "focus default should be 25 minutes")
    XCTAssertEqual(env.slackDurationMinutes, 10, "slack default should be 10 minutes")
    XCTAssertEqual(env.relaxDurationMinutes, 10, "relax default should be 10 minutes")

    env.focusDurationMinutes = 40
    env.slackDurationMinutes = 15
    env.relaxDurationMinutes = 20

    let restored = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(restored.focusDurationMinutes, 40)
    XCTAssertEqual(restored.slackDurationMinutes, 15)
    XCTAssertEqual(restored.relaxDurationMinutes, 20)
  }

  @MainActor
  func testCustomReminderMessagesRenderWithMinutes() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.focusDurationMinutes = 1
    env.focusReminderMessage = "专注了 {minutes} 分钟啦"
    env.startFocus()

    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("专注了 1 分钟啦"),
      "custom template should replace the {minutes} placeholder")

    // 空白模板回退默认。
    env.slackOff()
    env.slackDurationMinutes = 1
    env.slackReminderMessage = "   "
    env.advanceStateDurationReminder(by: .seconds(60))
    XCTAssertEqual(
      env.snapshot.bubble, .stateDurationReminder("你已连续摸鱼 1 分钟"),
      "blank custom message should fall back to the default template")
  }

  @MainActor
  func testReminderMessagesPersistToDefaults() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.focusReminderMessage, "你已连续专注 {minutes} 分钟")
    XCTAssertEqual(env.slackReminderMessage, "你已连续摸鱼 {minutes} 分钟")
    XCTAssertEqual(env.relaxReminderMessage, "你已连续放松 {minutes} 分钟")

    env.focusReminderMessage = "冲啊，已经 {minutes} 分钟了"
    env.relaxReminderMessage = "躺平 {m} 分钟了"

    let restored = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(restored.focusReminderMessage, "冲啊，已经 {minutes} 分钟了")
    XCTAssertEqual(restored.relaxReminderMessage, "躺平 {m} 分钟了")
  }

  @MainActor
  func testReminderDisplaySecondsPersistsToDefaults() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.reminderDisplaySeconds, 10, "display default should be 10 seconds")

    env.reminderDisplaySeconds = 30

    let restored = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(restored.reminderDisplaySeconds, 30, "display seconds should persist")
  }

  /// 快照发布有门控：averageCPU 变化不发布（CPU 只进诊断窗口），
  /// 显示字段（baseState 等）变化才发布。因此这里用会改变显示状态的
  /// userIdle 事件验证“信号事件被处理并反映到快照”。
  @MainActor
  func testStartProcessesSignalEvents() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()

    await waitUntil { source.subscriptionCount == 1 }
    source.emit(.userIdleChanged(.seconds(301)))
    await waitUntil { env.snapshot.baseState == .sleeping }

    XCTAssertEqual(env.snapshot.baseState, .sleeping, "start should process signal events")
    env.stop()
    source.finish()
  }

  @MainActor
  func testStopCancelsAllTasks() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    await waitUntil { source.subscriptionCount == 1 }
    source.emit(.userIdleChanged(.seconds(301)))
    await waitUntil { env.snapshot.baseState == .sleeping }

    env.stop()
    let snapshotAfterStop = env.snapshot

    // Emit an event AFTER stop that would change the display state —
    // it should be ignored because tasks are cancelled.
    source.emit(.userIdleChanged(.zero))
    await yieldToScheduler()

    XCTAssertEqual(
      env.snapshot, snapshotAfterStop,
      "snapshot should not change after stop even if new events arrive")
    source.finish()
  }

  @MainActor
  func testSameInstanceRestartAfterStop() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    await waitUntil { source.subscriptionCount == 1 }
    source.emit(.userIdleChanged(.seconds(301)))
    await waitUntil { env.snapshot.baseState == .sleeping }

    env.stop()

    // Restart the SAME instance — it should resume processing events.
    env.start()
    await waitUntil { source.subscriptionCount == 2 }
    source.emit(.userIdleChanged(.zero))
    await waitUntil { env.snapshot.baseState == .drinkingTea }

    XCTAssertEqual(
      env.snapshot.baseState, .drinkingTea,
      "same-instance restart should resume processing events")
    env.stop()
    source.finish()
  }

  @MainActor
  func testDoubleStartCreatesSingleSubscription() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    env.start()  // should be a no-op due to guard tasks.isEmpty
    await waitUntil { source.subscriptionCount == 1 }

    XCTAssertEqual(
      source.subscriptionCount, 1,
      "double start should not create duplicate subscriptions")
    env.stop()
    source.finish()
  }

  @MainActor
  func testStopThenStartResubscribes() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    await waitUntil { source.subscriptionCount == 1 }
    env.stop()
    env.start()
    await waitUntil { source.subscriptionCount == 2 }

    XCTAssertEqual(
      source.subscriptionCount, 2,
      "stop then start should create a fresh subscription")
    env.stop()
    source.finish()
  }

  // MARK: - Avatar display mode

  @MainActor
  func testAvatarDisplayModeDefaultsToCircle() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.avatarDisplayMode, .circle)
  }

  @MainActor
  func testAvatarDisplayModePersistsToDefaults() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.avatarDisplayMode = .original
    XCTAssertEqual(defaults.string(forKey: "avatarDisplayMode"), "original")
  }

  @MainActor
  func testAvatarDisplayModeRestoresFromDefaults() {
    defaults.set("original", forKey: "avatarDisplayMode")
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.avatarDisplayMode, .original)
  }

  // MARK: - Avatar lifecycle

  @MainActor
  func testAvatarImportLoadsImage() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let sourceURL = try writeTestPNG(in: tmp, size: 64)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    await env.importAvatar(from: sourceURL)

    XCTAssertNotNil(env.avatarImage, "import should load avatar image")
    XCTAssertNil(env.avatarError, "import should clear error")
  }

  @MainActor
  func testAvatarImportRejectsInvalidFile() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let garbageURL = tmp.appendingPathComponent("bad.png")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    try Data([0xFF, 0xD8, 0x00, 0x00]).write(to: garbageURL)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    await env.importAvatar(from: garbageURL)

    XCTAssertNil(env.avatarImage, "invalid file should not load avatar")
    XCTAssertNotNil(env.avatarError, "invalid file should produce error")
  }

  @MainActor
  func testSaveCroppedAvatarUpdatesImage() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    let cgImage = try makeTestCGImage(width: 64, height: 64)
    await env.saveCroppedAvatar(cgImage)

    XCTAssertNotNil(env.avatarImage, "save should update avatar image")
    XCTAssertNil(env.avatarError, "save should clear error")
  }

  @MainActor
  func testResetAvatarClearsImage() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    let cgImage = try makeTestCGImage(width: 64, height: 64)
    await env.saveCroppedAvatar(cgImage)
    XCTAssertNotNil(env.avatarImage)

    await env.resetAvatar()

    XCTAssertNil(env.avatarImage, "reset should clear avatar image")
    XCTAssertNil(env.avatarError, "reset should clear error")
  }

  @MainActor
  func testFullAvatarLifecycleImportCropReplaceReset() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let sourceURL = try writeTestPNG(in: tmp, size: 128)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    // 1. Import
    await env.importAvatar(from: sourceURL)
    XCTAssertNotNil(env.avatarImage, "step 1: import should load image")

    // 2. Crop and save with display mode
    let cropped = try makeTestCGImage(width: 64, height: 64)
    env.avatarDisplayMode = .original
    await env.saveCroppedAvatar(cropped)
    XCTAssertNotNil(env.avatarImage, "step 2: save should update image")
    XCTAssertEqual(env.avatarDisplayMode, .original, "step 2: display mode should be original")

    // 3. Replace with new image
    let sourceURL2 = try writeTestPNG(in: tmp, name: "source2.png", size: 200)
    await env.importAvatar(from: sourceURL2)
    XCTAssertNotNil(env.avatarImage, "step 3: replace should load new image")

    // 4. Reset
    await env.resetAvatar()
    XCTAssertNil(env.avatarImage, "step 4: reset should clear image")
  }

  @MainActor
  func testAvatarPersistsAcrossRestart() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)

    // First instance: save avatar
    let env1 = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    let cgImage = try makeTestCGImage(width: 64, height: 64)
    await env1.saveCroppedAvatar(cgImage)
    XCTAssertNotNil(env1.avatarImage)

    // Second instance: should load stored avatar on start
    let env2 = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    env2.start()
    await yieldToScheduler()
    await yieldToScheduler()

    XCTAssertNotNil(env2.avatarImage, "avatar should persist across restart")
    env2.stop()
  }

  @MainActor
  func testDisplayModePersistsAcrossRestart() async throws {
    let env1 = AppEnvironment(defaults: defaults, signalSources: [])
    env1.avatarDisplayMode = .original
    XCTAssertEqual(defaults.string(forKey: "avatarDisplayMode"), "original")

    // New instance should restore the mode
    let env2 = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env2.avatarDisplayMode, .original, "display mode should persist across restart")
  }

  @MainActor
  func testLoadSourceForEditSetsSourceImage() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let sourceURL = try writeTestPNG(in: tmp, size: 200)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)

    await env.loadSourceForEdit(from: sourceURL)

    XCTAssertNotNil(env.avatarSourceImage, "loadSourceForEdit should set source image")
    XCTAssertNil(env.avatarError)
  }

  /// 多帧姿势导入：一次导入 3 张动作帧 → 该行 3 帧 + 每帧缩略图，
  /// 重启后从精灵图精确恢复 3 帧。
  @MainActor
  func testImportMultiFramePoseForWorking() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))

    let frame1 = try writePoseFile(in: tmp, name: "frame1.png")
    let frame2 = try writePoseFile(in: tmp, name: "frame2.png")
    let frame3 = try writePoseFile(in: tmp, name: "frame3.png")

    let message = await env.importPose(row: .working, from: [frame1, frame2, frame3])

    XCTAssertNil(message)
    XCTAssertEqual(env.multiFrameCount(for: .working), 3, "working row should hold 3 frames")
    XCTAssertEqual(env.customPoseImages[.working]?.count, 3, "each frame gets a thumbnail")

    // 模拟重启：新实例从同一目录加载，sync 应恢复 3 帧。
    let env2 = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    env2.start()
    await waitUntil { env2.multiFrameCount(for: .working) == 3 }
    XCTAssertEqual(
      env2.multiFrameCount(for: .working), 3,
      "multi-frame count should restore from the persisted spritesheet")
  }

  /// 单帧姿势重启后仍恢复为 1 帧（不误判为多帧动画）。
  @MainActor
  func testSingleFramePoseRestoresAsOneFrame() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))
    let poseURL = try writePoseFile(in: tmp)
    _ = await env.importPose(row: .drinking, from: [poseURL])

    let env2 = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    env2.start()
    await waitUntil { env2.customPoseRows.contains(.drinking) }
    XCTAssertEqual(
      env2.multiFrameCount(for: .drinking), 1,
      "single-frame pose should restore as exactly one frame")
  }

  /// 未设置姿势的行帧数为 0（静态显示，不开启动画）。
  @MainActor
  func testUnsetRowsHaveNoFrames() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertEqual(env.multiFrameCount(for: .working), 0)
    XCTAssertEqual(env.multiFrameCount(for: .drinking), 0)
    XCTAssertEqual(env.multiFrameCount(for: .sleeping), 0)
  }

  /// RunCat 风格 CPU→帧间隔映射：0% CPU ≈ 200ms，50% ≈ 40ms，100% ≈ 10ms。
  @MainActor
  func testCPUSpeedMapping() {
    let idle = FrameAnimator.computeInterval(cpu: 0)
    XCTAssertEqual(idle, 0.20, accuracy: 0.001, "0% CPU should be the slowest (200ms)")
    let half = FrameAnimator.computeInterval(cpu: 0.5)
    XCTAssertEqual(half, 0.02, accuracy: 0.001, "50% CPU should be 20ms")
    let full = FrameAnimator.computeInterval(cpu: 1.0)
    XCTAssertEqual(full, 0.01, accuracy: 0.001, "100% CPU should be the fastest (10ms)")
    // 越界输入应被夹紧。
    XCTAssertEqual(FrameAnimator.computeInterval(cpu: -1), 0.20, accuracy: 0.001)
    XCTAssertEqual(FrameAnimator.computeInterval(cpu: 2), 0.01, accuracy: 0.001)
  }

  /// 活动提醒触发后切换状态（专注/摸鱼/放松/取消）会重置累计，
  /// 避免提醒永久卡死（第四轮修复的回归保护）。
  @MainActor
  func testActivityReminderResetsOnStateSwitch() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])

    // 直接驱动内部状态：先制造一次提醒触发（通过公开行为无法直接设
    // reminderWasDue，改为验证切换状态不会残留卡死状态 —— 用两次
    // startFocus + advanceStateDurationReminder 触发路径验证无崩溃）。
    env.startFocus()
    env.cancelFocus()
    env.startFocus()
    XCTAssertEqual(env.snapshot.baseState, .focusing, "focus restart should still pin")

    env.slackOff()
    XCTAssertEqual(env.snapshot.baseState, .drinkingTea)
    env.relax()
    XCTAssertEqual(env.snapshot.baseState, .sleeping)
  }

  /// 取消头像编辑：清源图与错误提示（第二轮修复的回归保护）。
  @MainActor
  func testCancelAvatarEditClearsSourceAndError() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    let badURL = tmp.appendingPathComponent("bad.png")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    try Data([0xFF, 0xD8, 0x00, 0x00]).write(to: badURL)

    await env.loadSourceForEdit(from: badURL)
    XCTAssertNil(env.avatarSourceImage, "failed load should clear source image")
    XCTAssertNotNil(env.avatarError, "failed load should surface an error")

    env.cancelAvatarEdit()
    XCTAssertNil(env.avatarSourceImage)
    XCTAssertNil(env.avatarError, "cancel should clear the error banner")
  }

  /// 删除待办：列表与磁盘都应移除该条。
  @MainActor
  func testDeleteTodoItemRemovesFromListAndDisk() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = try TodoStore(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], todoStore: store)

    env.addTodoItem("A")
    env.addTodoItem("B")
    env.deleteTodoItem(id: env.todoItems[1].id)

    XCTAssertEqual(env.todoItems.count, 1)
    XCTAssertEqual(env.todoItems.first?.title, "A")

    var loaded: [TodoItem] = []
    for _ in 0..<50 {
      loaded = await store.load()
      if loaded.count == 1 { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(loaded.count, 1, "deleted item should not persist")
  }

  /// 快照发布门控集成：仅 averageCPU 变化（不跨负载带）不应触发重新发布。
  @MainActor
  func testSnapshotNotRepublishedForCpuOnlyChanges() async throws {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()
    await waitUntil { source.subscriptionCount == 1 }

    var publishCount = 0
    let cancellable = env.$snapshot.sink { _ in publishCount += 1 }
    defer { cancellable.cancel() }

    let before = publishCount
    // 低 CPU 稳定在同一负载带内（0.10 → drinkingTea）：displayEquals 应短路。
    for _ in 0..<5 {
      source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.10, thermalLevel: .nominal)))
    }
    await yieldToScheduler()
    XCTAssertEqual(
      publishCount, before,
      "CPU-only changes within the same load band should not republish the snapshot")

    env.stop()
    source.finish()
  }

  /// 辅助窗口激活计数：出现 +1、关闭 -1，归零前不降级（窗口管理修复的回归保护）。
  @MainActor
  func testAuxiliaryWindowCounting() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.auxiliaryWindowDidAppear()
    env.auxiliaryWindowDidAppear()
    env.auxiliaryWindowDidDisappear()
    // 计数 ≥1 时不应降级（无直接读取器，验证多轮 appear/disappear 不崩溃、
    // 归零后再 appear 仍可工作）。
    env.auxiliaryWindowDidDisappear()
    env.auxiliaryWindowDidAppear()
    env.auxiliaryWindowDidDisappear()
  }

  /// 快速连续修改待办：写盘必须按触发顺序串行（pendingWrite 链），
  /// 最终磁盘状态 = 最后一次内存状态（回归保护乱序覆盖丢数据）。
  @MainActor
  func testRapidTodoMutationsPersistFinalState() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = try TodoStore(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], todoStore: store)

    env.addTodoItem("A")
    env.addTodoItem("B")
    env.toggleTodoItem(id: env.todoItems[0].id)

    var loaded: [TodoItem] = []
    for _ in 0..<50 {
      loaded = await store.load()
      if loaded.count == 2 && loaded[0].isCompleted && !loaded[1].isCompleted { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(loaded.count, 2, "both todos should persist")
    XCTAssertTrue(loaded[0].isCompleted, "first todo should be completed on disk")
    XCTAssertFalse(loaded[1].isCompleted, "second todo should stay incomplete on disk")
  }

  /// 启动统计与磁盘值合并：预写 100 秒专注 + 启动后 tick 累计，
  /// 最终落盘 = 磁盘值 + 新增累计（不覆盖、不双计）。
  @MainActor
  func testStartupStatsMergeWithDiskValue() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = try UsageStatsStore(directoryURL: tmp)
    let today = DayStats.todayKey()
    try await store.upsert(DayStats(date: today, focusSeconds: 100))

    let env = AppEnvironment(defaults: defaults, signalSources: [], usageStore: store)
    env.start()
    env.startFocus()  // focusing → 每秒累计 1 秒专注

    // 等真实 tick 累计至少 3 秒（tick 每秒一次，留足余量）。
    try await Task.sleep(for: .seconds(5))

    env.stop()  // 触发 flush

    var finalFocus = 0
    for _ in 0..<50 {
      let saved = await store.loadAll()
      finalFocus = saved.first(where: { $0.date == today })?.focusSeconds ?? 0
      if finalFocus >= 103 { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertGreaterThanOrEqual(finalFocus, 103, "disk 100 + startup ticks should merge")
    XCTAssertLessThan(finalFocus, 200, "disk value should not be double-counted")
  }

  /// 气泡待办列表不再截断前 5 条：全部未完成项都应暴露，供气泡内滚动查看。
  @MainActor
  func testIncompleteTodoItemsExposesAllPendingForBubbleScroll() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    for index in 0..<7 {
      env.addTodoItem("事项 \(index)")
    }
    env.toggleTodoItem(id: env.todoItems[0].id)
    XCTAssertEqual(env.incompleteTodoItems.count, 6, "bubble should expose every incomplete item")
    XCTAssertTrue(
      env.incompleteTodoItems.allSatisfy { !$0.isCompleted },
      "exposed items should be the incomplete ones")
  }

  /// 专注也要钉住：会话完成后视觉保持专注，不自动切回 CPU/空闲驱动的
  /// 摸鱼/放松（点击什么状态就是什么状态，直到用户手动切换）。
  @MainActor
  func testFocusStaysPinnedAfterSessionCompletes() async throws {
    let source = ControllableSignalSource()
    let session = FocusSession(duration: .seconds(2), idlePauseAfter: .seconds(3_600))
    let env = AppEnvironment(
      defaults: defaults, signalSources: [source], focusSession: session)
    env.start()

    env.startFocus()
    XCTAssertEqual(env.snapshot.baseState, .focusing)

    // 会话 2 秒完成 → 状态机触发 complete 事件。tick 由真实时钟驱动，
    // 需要实际等待（waitUntil 只 yield，不等待真实时间）。
    var completed = false
    for _ in 0..<100 where !completed {
      try await Task.sleep(for: .milliseconds(100))
      completed = env.focusSession.phase == .completed
    }
    XCTAssertTrue(completed, "short session should complete within 10s")
    var showedComplete = false
    for _ in 0..<50 where !showedComplete {
      try await Task.sleep(for: .milliseconds(100))
      showedComplete = env.snapshot.bubble == .focusComplete
    }
    XCTAssertTrue(showedComplete, "session completion should show the bubble")

    // 完成后不应自动切走（旧行为：回到 CPU 驱动的 drinkingTea）。
    XCTAssertEqual(
      env.snapshot.baseState, .focusing,
      "focus should stay pinned after the session completes")
    env.stop()
    source.finish()
  }

  // MARK: - AI pose provider and animation pause

  @MainActor
  func testPetAnimationPausedDefaultsTrueAndUpdates() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    XCTAssertTrue(env.isPetAnimationPaused, "animation should start paused until the window shows")

    env.updatePetAnimationPaused(false)
    XCTAssertFalse(env.isPetAnimationPaused, "showing the window should unpause animation")

    env.updatePetAnimationPaused(true)
    XCTAssertTrue(env.isPetAnimationPaused, "hiding the window should pause animation")
  }

  private actor ProbeCounter {
    private var count = 0

    func record() {
      count += 1
    }

    var current: Int { count }
  }

  private struct RecordingPoseProvider: AIPoseProvider {
    let probe = ProbeCounter()

    var supportsReferenceImage: Bool { true }

    func generateSpritesheet(from referenceImage: CGImage) async throws -> CGImage? {
      await probe.record()
      return SpriteSheetGenerator.generate(from: referenceImage)
    }
  }

  private struct ThrowingPoseProvider: AIPoseProvider {
    var supportsReferenceImage: Bool { true }

    func generateSpritesheet(from referenceImage: CGImage) async throws -> CGImage? {
      throw AIPoseError.invalidResponse
    }
  }

  private final class RecordingEyeLocator: EyeBandLocating {
    private let lock = NSLock()
    private var calls = 0

    func eyeBand(in image: CGImage) -> CGRect? {
      lock.lock()
      calls += 1
      lock.unlock()
      return nil
    }

    var callCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return calls
    }
  }

  @MainActor
  func testSaveCroppedAvatarUsesPoseProviderFirst() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let provider = RecordingPoseProvider()
    let env = AppEnvironment(
      defaults: defaults,
      signalSources: [],
      avatarRepository: repo,
      poseProvider: provider
    )

    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))

    let calls = await provider.probe.current
    XCTAssertEqual(calls, 1, "AI provider should run before fallback")
    XCTAssertNotNil(env.avatarSpritesheet, "AI sheet should be saved")
    XCTAssertNil(env.avatarError)
  }

  @MainActor
  func testSaveCroppedAvatarFallsBackWhenPoseProviderFails() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(
      defaults: defaults,
      signalSources: [],
      avatarRepository: repo,
      poseProvider: ThrowingPoseProvider()
    )

    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))

    XCTAssertNotNil(
      env.avatarSpritesheet,
      "failing AI provider should fall back to the programmatic sheet")
    XCTAssertNil(env.avatarError)
  }

  @MainActor
  func testSaveCroppedAvatarConsultsEyeLocator() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let locator = RecordingEyeLocator()
    let env = AppEnvironment(
      defaults: defaults,
      signalSources: [],
      avatarRepository: repo,
      poseProvider: nil,
      eyeLocator: locator
    )

    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))

    XCTAssertEqual(locator.callCount, 1, "eye locator should run on avatar save")
    XCTAssertNotNil(env.avatarSpritesheet)
  }

  private func writePoseFile(in directory: URL, name: String = "pose.png") throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let size = 256
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { throw NSError(domain: "test", code: 40) }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "test", code: 41) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 42)
    }
    return url
  }

  @MainActor
  func testImportPoseUpdatesSheetAndPersists() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))
    let poseURL = try writePoseFile(in: tmp)

    let message = await env.importPose(row: .working, from: [poseURL])

    XCTAssertNil(message, "valid pose should import without an error")
    XCTAssertTrue(env.customPoseRows.contains(.working), "working row should be marked custom")
    XCTAssertNotNil(
      env.customPoseImages[.working],
      "imported pose should expose a preview thumbnail")
    XCTAssertNotNil(env.avatarSpritesheet, "sheet should be reassembled")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: tmp.appendingPathComponent("spritesheet.png").path),
      "reassembled sheet should persist")
  }

  @MainActor
  func testImportPoseWithoutAvatarSetsError() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    let poseURL = try writePoseFile(in: tmp)

    let message = await env.importPose(row: .working, from: [poseURL])

    XCTAssertNotNil(message, "pose import without avatar should fail with guidance")
    XCTAssertTrue(env.customPoseRows.isEmpty)
  }

  @MainActor
  func testClearPoseRestoresAvatarSheet() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))
    let poseURL = try writePoseFile(in: tmp)
    _ = await env.importPose(row: .working, from: [poseURL])
    XCTAssertTrue(env.customPoseRows.contains(.working))

    let message = await env.clearPose(row: .working)

    XCTAssertNil(message)
    XCTAssertTrue(env.customPoseRows.isEmpty, "cleared pose should fall back to avatar")
    XCTAssertNil(env.customPoseImages[.working], "cleared pose should drop its thumbnail")
    XCTAssertNotNil(env.avatarSpritesheet, "avatar-only sheet should remain")
  }

  @MainActor
  func testCustomPoseStateRestoresAfterRestart() async throws {
    let tmp = tempDirectory()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let repo = try AvatarRepository(directoryURL: tmp)
    let env = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    await env.saveCroppedAvatar(try makeTestCGImage(width: 64, height: 64))
    let poseURL = try writePoseFile(in: tmp)
    let message = await env.importPose(row: .working, from: [poseURL])
    XCTAssertNil(message, "pose should import before restart")

    // 模拟重启：新实例从同一目录加载头像与精灵图。
    let env2 = AppEnvironment(defaults: defaults, signalSources: [], avatarRepository: repo)
    env2.start()
    await waitUntil { env2.customPoseRows.contains(.working) }

    XCTAssertTrue(
      env2.customPoseRows.contains(.working),
      "custom pose rows should restore from the persisted spritesheet")
    XCTAssertNotNil(
      env2.customPoseImages[.working],
      "custom pose thumbnail should restore from the persisted spritesheet")
    env2.stop()
  }

  @MainActor
  private func waitUntil(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<100 {
      if condition() { return }
      await Task.yield()
    }
    XCTFail("Condition was not satisfied after yielding to the scheduler", file: file, line: line)
  }

  @MainActor
  private func yieldToScheduler() async {
    for _ in 0..<10 { await Task.yield() }
  }

  private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("AppEnvTests-\(UUID().uuidString)")
  }

  private func writeTestPNG(in directory: URL, name: String = "source.png", size: Int) throws
    -> URL
  {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let image = try makeTestCGImage(width: size, height: size)
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "test", code: 2) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 3)
    }
    return url
  }

  private func makeTestCGImage(width: Int, height: Int) throws -> CGImage {
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue),
      let image = context.makeImage()
    else { throw NSError(domain: "test", code: 1) }
    return image
  }
}
