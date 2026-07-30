import Foundation

public struct ActivityReminderAccumulator: Sendable, Equatable {
  public private(set) var isDue = false
  public private(set) var activeElapsed: Duration = .zero

  private let remindAfter: Duration
  private let snoozeFor: Duration
  private let idlePauseAfter: Duration
  private var snoozeRemaining: Duration = .zero

  public init(
    remindAfter: Duration = .seconds(3_600),
    snoozeFor: Duration = .seconds(600),
    idlePauseAfter: Duration = .seconds(60)
  ) {
    self.remindAfter = remindAfter
    self.snoozeFor = snoozeFor
    self.idlePauseAfter = idlePauseAfter
  }

  public mutating func advance(by elapsed: Duration, userIdle: Duration) {
    guard userIdle < idlePauseAfter else { return }
    let elapsed = max(elapsed, .zero)
    if snoozeRemaining > .zero {
      snoozeRemaining -= elapsed
      if snoozeRemaining <= .zero {
        snoozeRemaining = .zero
        isDue = true
      }
      return
    }
    guard !isDue else { return }
    activeElapsed += elapsed
    if activeElapsed >= remindAfter { isDue = true }
  }

  public mutating func snooze() {
    isDue = false
    snoozeRemaining = snoozeFor
  }

  public mutating func acknowledgeBreak() {
    isDue = false
    activeElapsed = .zero
    snoozeRemaining = .zero
  }
}
