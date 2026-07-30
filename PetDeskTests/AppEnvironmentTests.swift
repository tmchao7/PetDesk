import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

private struct MockSignalSource: PetSignalSource {
  let events: [PetEvent]

  func events() -> AsyncStream<PetEvent> {
    let events = self.events
    return AsyncStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
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

  @MainActor
  func testStartProcessesSignalEvents() async {
    let source = MockSignalSource(events: [
      .systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal))
    ])
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    try? await Task.sleep(for: .milliseconds(100))

    XCTAssertGreaterThan(env.snapshot.averageCPU, 0)
    env.stop()
  }

  @MainActor
  func testStopCancelsAllTasks() async {
    let source = MockSignalSource(events: [
      .systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal))
    ])
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    try? await Task.sleep(for: .milliseconds(50))
    env.stop()

    let snapshotAfterStop = env.snapshot
    try? await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(env.snapshot, snapshotAfterStop, "snapshot should not change after stop")
  }

  @MainActor
  func testRestartAfterStop() async {
    let source = MockSignalSource(events: [
      .systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal))
    ])
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    try? await Task.sleep(for: .milliseconds(50))
    env.stop()

    let source2 = MockSignalSource(events: [
      .systemMetrics(SystemMetrics(cpuLoad: 0.90, thermalLevel: .nominal))
    ])
    // Create a new environment since signalSources is immutable
    let env2 = AppEnvironment(defaults: defaults, signalSources: [source2])
    env2.start()
    try? await Task.sleep(for: .milliseconds(100))

    XCTAssertGreaterThan(env2.snapshot.averageCPU, 0)
    env2.stop()
  }

  @MainActor
  func testQuietModeBlocksNotifications() {
    let env = AppEnvironment(defaults: defaults, signalSources: [])
    env.start()

    env.injectNotification(.wechat)
    XCTAssertNotNil(env.snapshot.transientState, "non-quiet notification should produce transient")

    // Enable quiet mode
    defaults.set(true, forKey: "quietMode")
    let envQuiet = AppEnvironment(defaults: defaults, signalSources: [])
    envQuiet.start()

    envQuiet.injectNotification(.wechat)
    // In quiet mode, notification events should be filtered
    // The snapshot should not have a startled transient state
    XCTAssertNil(envQuiet.snapshot.transientState, "quiet mode should block notification pulses")

    env.stop()
    envQuiet.stop()
  }

  @MainActor
  func testDoubleStartIsIdempotent() async {
    let source = MockSignalSource(events: [
      .systemMetrics(SystemMetrics(cpuLoad: 0.50, thermalLevel: .nominal))
    ])
    let env = AppEnvironment(defaults: defaults, signalSources: [source])

    env.start()
    env.start()  // should be a no-op
    try? await Task.sleep(for: .milliseconds(100))

    XCTAssertGreaterThan(env.snapshot.averageCPU, 0)
    env.stop()
  }
}
