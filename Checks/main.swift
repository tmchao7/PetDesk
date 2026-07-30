import Foundation
import PetDeskCore

private struct CheckFailure: Error, CustomStringConvertible {
  let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw CheckFailure(description: message) }
}

private func feed(cpu: Double, seconds: Int, to machine: inout PetStateMachine) {
  for _ in 0..<seconds {
    machine.reduce(
      .systemMetrics(SystemMetrics(cpuLoad: cpu, thermalLevel: .nominal)),
      elapsed: .seconds(1)
    )
  }
}

private func checkStateMachine() throws {
  var normal = PetStateMachine()
  feed(cpu: 0.50, seconds: 10, to: &normal)
  try expect(normal.snapshot.baseState == .working, "normal CPU should enter working")

  var busy = PetStateMachine()
  feed(cpu: 0.70, seconds: 15, to: &busy)
  try expect(busy.snapshot.baseState == .jogging, "busy CPU should enter jogging")
  feed(cpu: 0.58, seconds: 20, to: &busy)
  try expect(busy.snapshot.baseState == .jogging, "hysteresis should prevent flapping")

  var hot = PetStateMachine()
  feed(cpu: 0.90, seconds: 15, to: &hot)
  try expect(hot.snapshot.baseState == .running, "hot CPU should enter running")
  hot.reduce(.userIdleChanged(.seconds(301)), elapsed: .zero)
  try expect(hot.snapshot.baseState == .sleeping, "idle should override CPU")
  hot.reduce(.focusCommand(.start), elapsed: .zero)
  try expect(hot.snapshot.baseState == .focusing, "focus should override idle")

  var transient = PetStateMachine()
  transient.reduce(.notificationPulse(.wechat), elapsed: .zero)
  transient.reduce(.tick(.seconds(2)), elapsed: .seconds(2))
  try expect(transient.snapshot.transientState == .startled(.wechat), "startle ended too early")
  transient.reduce(.tick(.milliseconds(500)), elapsed: .milliseconds(500))
  try expect(transient.snapshot.transientState == nil, "startle did not expire")

  var thermal = PetStateMachine()
  thermal.reduce(
    .systemMetrics(SystemMetrics(cpuLoad: 0.10, thermalLevel: .critical)),
    elapsed: .seconds(1)
  )
  try expect(thermal.snapshot.effects.contains(.smoke), "critical thermal state should add smoke")

  var sleeping = PetStateMachine()
  sleeping.reduce(.userIdleChanged(.seconds(301)), elapsed: .zero)
  try expect(sleeping.snapshot.baseState == .sleeping, "idle timeout should enter sleeping")
  try expect(sleeping.snapshot.effects == [.zzz], "sleeping state should have zzz effect")

  var activity = PetStateMachine()
  activity.reduce(.focusCommand(.showActivityReminder), elapsed: .zero)
  try expect(activity.snapshot.transientState == .stretching, "activity reminder should stretch")
  try expect(activity.snapshot.bubble == .stretchReminder, "activity reminder should show a bubble")
  activity.reduce(.focusCommand(.snoozeActivity), elapsed: .zero)
  try expect(
    activity.snapshot.transientState == nil && activity.snapshot.bubble == nil,
    "snooze should clear reminder")
}

private func checkCoreServices() throws {
  var calculator = CPULoadCalculator()
  try expect(
    calculator.record(CPUTicks(user: 100, system: 100, idle: 200, nice: 0)) == nil,
    "first CPU sample must establish baseline")
  let load = calculator.record(CPUTicks(user: 150, system: 150, idle: 300, nice: 0))
  try expect(abs((load ?? -1) - 0.5) < 0.0001, "CPU load should use tick deltas")
  try expect(
    calculator.record(CPUTicks(user: 10, system: 10, idle: 20, nice: 0)) == nil,
    "CPU rollback should reset baseline")

  var idleCalc = CPULoadCalculator()
  _ = idleCalc.record(CPUTicks(user: 0, system: 0, idle: 1_000, nice: 0))
  let idleLoad = idleCalc.record(CPUTicks(user: 0, system: 0, idle: 2_000, nice: 0))
  if let load = idleLoad {
    try expect(abs(load - 0.0) < 0.0001, "idle CPU should return zero load")
  } else {
    throw CheckFailure(description: "idle CPU should return a non-nil load")
  }

  var focus = FocusSession(duration: .seconds(120), idlePauseAfter: .seconds(60))
  focus.start()
  focus.advance(by: .seconds(30), userIdle: .seconds(90))
  try expect(focus.remaining == .seconds(120), "idle focus time should not count")
  focus.advance(by: .seconds(120), userIdle: .zero)
  try expect(focus.phase == .completed, "active focus time should complete session")

  var reminder = ActivityReminderAccumulator(remindAfter: .seconds(3_600), snoozeFor: .seconds(600))
  reminder.advance(by: .seconds(3_600), userIdle: .zero)
  try expect(reminder.isDue, "activity reminder should become due")
  reminder.snooze()
  reminder.advance(by: .seconds(600), userIdle: .zero)
  try expect(reminder.isDue, "snoozed activity reminder should return")

  reminder.acknowledgeBreak()
  try expect(!reminder.isDue, "acknowledgeBreak should clear isDue")
  try expect(reminder.activeElapsed < .seconds(1), "acknowledgeBreak should reset activeElapsed")
  reminder.advance(by: .seconds(3_599), userIdle: .zero)
  try expect(!reminder.isDue, "reminder should not be due after partial re-accumulation")

  let avatarPolicy = AvatarImportPolicy()
  do {
    try avatarPolicy.validate(byteCount: 20 * 1_024 * 1_024 + 1, fileExtension: "png")
    throw CheckFailure(description: "oversized avatar was accepted")
  } catch AvatarImportError.fileTooLarge {
  }
  try avatarPolicy.validate(byteCount: 1_024, fileExtension: "heic")

  let clamped = ScreenPositionResolver.clamped(
    frame: CGRect(x: 1_200, y: -300, width: 180, height: 180),
    visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
  )
  try expect(clamped.origin == CGPoint(x: 820, y: 0), "window frame should be clamped")

  var deduplicator = NotificationPulseDeduplicator(cooldown: .seconds(3))
  try expect(deduplicator.shouldEmit(source: .wechat, at: .zero), "first notification should emit")
  try expect(
    !deduplicator.shouldEmit(source: .wechat, at: .seconds(2)),
    "duplicate notification should be dropped")
  try expect(
    deduplicator.shouldEmit(source: .qq, at: .seconds(2)),
    "different notification source should emit")

  var buffer = RingBuffer<Int>(capacity: 3)
  for value in 1...4 { buffer.append(value) }
  try expect(buffer.values == [2, 3, 4], "ring buffer should retain newest values")
}

do {
  try checkStateMachine()
  try checkCoreServices()
  print("PetDeskCoreChecks: all checks passed")
} catch {
  FileHandle.standardError.write(Data("PetDeskCoreChecks: \(error)\n".utf8))
  exit(1)
}
