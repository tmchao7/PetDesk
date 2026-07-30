import Synchronization
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
  func testStartProcessesSignalEvents() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])
    env.start()

    await waitUntil { source.subscriptionCount == 1 }
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await waitUntil { env.snapshot.averageCPU > 0 }

    XCTAssertGreaterThan(env.snapshot.averageCPU, 0, "start should process signal events")
    env.stop()
    source.finish()
  }

  @MainActor
  func testStopCancelsAllTasks() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    await waitUntil { source.subscriptionCount == 1 }
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await waitUntil { env.snapshot.averageCPU > 0 }

    env.stop()
    let snapshotAfterStop = env.snapshot

    // Emit another event AFTER stop — should be ignored because tasks are cancelled.
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.90, thermalLevel: .nominal)))
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
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await waitUntil { env.snapshot.averageCPU > 0 }
    XCTAssertGreaterThan(env.snapshot.averageCPU, 0)

    env.stop()

    // Restart the SAME instance — it should resume processing events.
    env.start()
    await waitUntil { source.subscriptionCount == 2 }
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.90, thermalLevel: .nominal)))
    await waitUntil { env.snapshot.averageCPU > 0.50 }

    XCTAssertGreaterThan(
      env.snapshot.averageCPU, 0.50,
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

  // MARK: - Quiet mode

  @MainActor
  func testQuietModeBlocksNotifications() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.start()

    env.injectNotification(.wechat)
    XCTAssertNotNil(env.snapshot.transientState, "non-quiet notification should produce transient")

    env.stop()

    defaults.set(true, forKey: "quietMode")
    let envQuiet = AppEnvironment(defaults: defaults, signalSources: [])
    envQuiet.start()

    envQuiet.injectNotification(.wechat)
    XCTAssertNil(
      envQuiet.snapshot.transientState, "quiet mode should block notification pulses")

    envQuiet.stop()
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
}
