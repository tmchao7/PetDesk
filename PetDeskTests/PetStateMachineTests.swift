import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class PetStateMachineTests: XCTestCase {
  func testSustainedNormalLoadEntersWorking() {
    var machine = PetStateMachine()

    feed(cpu: 0.50, seconds: 10, to: &machine)

    XCTAssertEqual(machine.snapshot.baseState, .working)
    XCTAssertTrue(machine.snapshot.effects.contains(.keyboard))
  }

  func testBusyAndHotLoadMapToActiveStates() {
    var busyMachine = PetStateMachine()
    var hotMachine = PetStateMachine()

    feed(cpu: 0.70, seconds: 15, to: &busyMachine)
    feed(cpu: 0.90, seconds: 15, to: &hotMachine)

    XCTAssertEqual(busyMachine.snapshot.baseState, .jogging)
    XCTAssertEqual(hotMachine.snapshot.baseState, .running)
    XCTAssertTrue(hotMachine.snapshot.effects.contains(.sweat))
  }

  func testHysteresisPreventsBoundaryFlapping() {
    var machine = PetStateMachine()
    feed(cpu: 0.70, seconds: 15, to: &machine)

    feed(cpu: 0.58, seconds: 20, to: &machine)

    XCTAssertEqual(machine.snapshot.baseState, .jogging)
  }

  func testIdleAndFocusOverrideCPU() {
    var machine = PetStateMachine()
    feed(cpu: 0.90, seconds: 15, to: &machine)

    machine.reduce(.userIdleChanged(.seconds(301)), elapsed: .zero)
    XCTAssertEqual(machine.snapshot.baseState, .sleeping)
    XCTAssertEqual(machine.snapshot.effects, [.zzz])

    machine.reduce(.focusCommand(.start), elapsed: .zero)
    XCTAssertEqual(machine.snapshot.baseState, .focusing)
    XCTAssertTrue(machine.snapshot.effects.contains(.keyboard))

    machine.reduce(.focusCommand(.cancel), elapsed: .zero)
    machine.reduce(.userIdleChanged(.zero), elapsed: .zero)
    XCTAssertEqual(machine.snapshot.baseState, .running)
  }

  func testThermalPressureAddsSmoke() {
    var machine = PetStateMachine()

    machine.reduce(
      .systemMetrics(SystemMetrics(cpuLoad: 0.10, thermalLevel: .serious)),
      elapsed: .seconds(1)
    )

    XCTAssertTrue(machine.snapshot.effects.contains(.smoke))
  }

  func testNotificationStartleExpires() {
    var machine = PetStateMachine()

    machine.reduce(.notificationPulse(.wechat), elapsed: .zero)
    XCTAssertEqual(machine.snapshot.transientState, .startled(.wechat))

    machine.reduce(.tick(.seconds(2)), elapsed: .seconds(2))
    XCTAssertEqual(machine.snapshot.transientState, .startled(.wechat))

    machine.reduce(.tick(.milliseconds(500)), elapsed: .milliseconds(500))
    XCTAssertNil(machine.snapshot.transientState)
  }

  func testFocusCompletionCelebrates() {
    var machine = PetStateMachine()

    machine.reduce(.focusCommand(.complete), elapsed: .zero)

    XCTAssertEqual(machine.snapshot.transientState, .celebrating)
    XCTAssertEqual(machine.snapshot.bubble, .focusComplete)
  }

  func testActivityReminderCanBeShownAndSnoozed() {
    var machine = PetStateMachine()

    machine.reduce(.focusCommand(.showActivityReminder), elapsed: .zero)
    XCTAssertEqual(machine.snapshot.transientState, .stretching)
    XCTAssertEqual(machine.snapshot.bubble, .stretchReminder)

    machine.reduce(.focusCommand(.snoozeActivity), elapsed: .zero)
    XCTAssertNil(machine.snapshot.transientState)
    XCTAssertNil(machine.snapshot.bubble)
  }

  private func feed(cpu: Double, seconds: Int, to machine: inout PetStateMachine) {
    for _ in 0..<seconds {
      machine.reduce(
        .systemMetrics(SystemMetrics(cpuLoad: cpu, thermalLevel: .nominal)),
        elapsed: .seconds(1)
      )
    }
  }
}
