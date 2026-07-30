import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class CoreServicesTests: XCTestCase {
  func testCPULoadUsesTickDeltasAndResetsAfterCounterRollback() {
    var calculator = CPULoadCalculator()
    XCTAssertNil(calculator.record(CPUTicks(user: 100, system: 100, idle: 200, nice: 0)))
    XCTAssertEqual(
      calculator.record(CPUTicks(user: 150, system: 150, idle: 300, nice: 0)),
      0.5,
      accuracy: 0.0001
    )
    XCTAssertNil(calculator.record(CPUTicks(user: 10, system: 10, idle: 20, nice: 0)))
  }

  func testFocusPausesForIdleAndCompletesOnlyOnActiveTime() {
    var session = FocusSession(duration: .seconds(120), idlePauseAfter: .seconds(60))
    session.start()

    session.advance(by: .seconds(30), userIdle: .seconds(90))
    XCTAssertEqual(session.remaining, .seconds(120))
    XCTAssertEqual(session.phase, .pausedForIdle)

    session.advance(by: .seconds(120), userIdle: .zero)
    XCTAssertEqual(session.remaining, .zero)
    XCTAssertEqual(session.phase, .completed)
  }

  func testActivityReminderCountsActiveTimeAndSupportsSnooze() {
    var reminder = ActivityReminderAccumulator(
      remindAfter: .seconds(3_600), snoozeFor: .seconds(600))
    reminder.advance(by: .seconds(3_600), userIdle: .zero)
    XCTAssertTrue(reminder.isDue)

    reminder.snooze()
    XCTAssertFalse(reminder.isDue)
    reminder.advance(by: .seconds(599), userIdle: .zero)
    XCTAssertFalse(reminder.isDue)
    reminder.advance(by: .seconds(1), userIdle: .zero)
    XCTAssertTrue(reminder.isDue)
  }

  func testAvatarPolicyRejectsOversizedAndUnsupportedFiles() throws {
    let policy = AvatarImportPolicy()
    XCTAssertThrowsError(
      try policy.validate(byteCount: 20 * 1_024 * 1_024 + 1, fileExtension: "png"))
    XCTAssertThrowsError(try policy.validate(byteCount: 1_024, fileExtension: "gif"))
    XCTAssertNoThrow(try policy.validate(byteCount: 1_024, fileExtension: "heic"))
  }

  func testScreenPositionIsClampedIntoVisibleFrame() {
    let visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let offscreen = CGRect(x: 1_200, y: -300, width: 180, height: 180)

    let result = ScreenPositionResolver.clamped(frame: offscreen, visibleFrames: [visible])

    XCTAssertEqual(result.origin.x, 820)
    XCTAssertEqual(result.origin.y, 0)
  }

  func testNotificationDeduplicatorDropsSameSourceInsideCooldown() {
    var deduplicator = NotificationPulseDeduplicator(cooldown: .seconds(3))

    XCTAssertTrue(deduplicator.shouldEmit(source: .wechat, at: .zero))
    XCTAssertFalse(deduplicator.shouldEmit(source: .wechat, at: .seconds(2)))
    XCTAssertTrue(deduplicator.shouldEmit(source: .qq, at: .seconds(2)))
    XCTAssertTrue(deduplicator.shouldEmit(source: .wechat, at: .seconds(3)))
  }

  func testRingBufferKeepsOnlyNewestValues() {
    var buffer = RingBuffer<Int>(capacity: 3)
    for value in 1...4 { buffer.append(value) }
    XCTAssertEqual(buffer.values, [2, 3, 4])
  }

  func testActivityReminderAcknowledgeBreakResetsAccumulator() {
    var reminder = ActivityReminderAccumulator(
      remindAfter: .seconds(3_600), snoozeFor: .seconds(600))

    reminder.advance(by: .seconds(3_600), userIdle: .zero)
    XCTAssertTrue(reminder.isDue)

    reminder.acknowledgeBreak()
    XCTAssertFalse(reminder.isDue)
    XCTAssertTrue(reminder.activeElapsed < .seconds(1))

    reminder.advance(by: .seconds(3_599), userIdle: .zero)
    XCTAssertFalse(reminder.isDue)
  }

  func testCPULoadReturnsZeroForIdleSystem() {
    var calculator = CPULoadCalculator()
    _ = calculator.record(CPUTicks(user: 0, system: 0, idle: 1_000, nice: 0))
    let load = calculator.record(CPUTicks(user: 0, system: 0, idle: 2_000, nice: 0))
    XCTAssertEqual(load, 0.0, accuracy: 0.0001)
  }

  func testScreenPositionResolverPrefersMostOverlappingScreen() {
    let leftScreen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let rightScreen = CGRect(x: 1_000, y: 0, width: 1_000, height: 800)
    // Left overlap: 150*200 = 30,000; right overlap: 50*200 = 10,000
    let frame = CGRect(x: 850, y: 100, width: 200, height: 200)

    let result = ScreenPositionResolver.clamped(
      frame: frame, visibleFrames: [leftScreen, rightScreen])

    XCTAssertTrue(
      leftScreen.contains(result),
      "result should be clamped into leftScreen which has more overlap")
  }
}
