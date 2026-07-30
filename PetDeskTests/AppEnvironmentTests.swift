import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// Controllable signal source: the test holds the continuation and emits
/// events on demand. The stream stays open until the continuation is
/// finished, so the receiving task does not terminate on its own.
private final class ControllableSignalSource: PetSignalSource, @unchecked Sendable {
  private var continuation: AsyncStream<PetEvent>.Continuation?

  func events() -> AsyncStream<PetEvent> {
    AsyncStream { continuation in
      self.continuation = continuation
    }
  }

  func emit(_ event: PetEvent) {
    continuation?.yield(event)
  }

  func finish() {
    continuation?.finish()
    continuation = nil
  }
}

/// Counts how many times `events()` is called, proving subscription count.
private final class SubscriptionCountingSource: PetSignalSource, @unchecked Sendable {
  private(set) var subscriptionCount = 0
  private var continuation: AsyncStream<PetEvent>.Continuation?

  func events() -> AsyncStream<PetEvent> {
    subscriptionCount += 1
    return AsyncStream { continuation in
      self.continuation = continuation
    }
  }

  func emit(_ event: PetEvent) {
    continuation?.yield(event)
  }

  func finish() {
    continuation?.finish()
    continuation = nil
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

    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await Task.yield()

    XCTAssertGreaterThan(env.snapshot.averageCPU, 0, "start should process signal events")
    env.stop()
    source.finish()
  }

  @MainActor
  func testStopCancelsAllTasks() async {
    let source = ControllableSignalSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await Task.yield()

    env.stop()
    let snapshotAfterStop = env.snapshot

    // Emit another event AFTER stop — should be ignored because tasks are cancelled.
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.90, thermalLevel: .nominal)))
    await Task.yield()

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
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal)))
    await Task.yield()
    XCTAssertGreaterThan(env.snapshot.averageCPU, 0)

    env.stop()

    // Restart the SAME instance — it should resume processing events.
    env.start()
    source.emit(.systemMetrics(SystemMetrics(cpuLoad: 0.90, thermalLevel: .nominal)))
    await Task.yield()

    XCTAssertGreaterThan(
      env.snapshot.averageCPU, 0.50,
      "same-instance restart should resume processing events")
    env.stop()
    source.finish()
  }

  @MainActor
  func testDoubleStartCreatesSingleSubscription() async {
    let source = SubscriptionCountingSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    env.start()  // should be a no-op due to guard tasks.isEmpty

    XCTAssertEqual(
      source.subscriptionCount, 1,
      "double start should not create duplicate subscriptions")
    env.stop()
    source.finish()
  }

  @MainActor
  func testStopThenStartResubscribes() async {
    let source = SubscriptionCountingSource()
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    env.stop()
    env.start()

    XCTAssertEqual(
      source.subscriptionCount, 2,
      "stop then start should create a fresh subscription")
    env.stop()
    source.finish()
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
}
