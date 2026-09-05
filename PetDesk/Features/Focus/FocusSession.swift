import Foundation

public enum FocusPhase: String, Sendable, Equatable, Codable {
  case idle
  case running
  case pausedForIdle
  case completed
}

public struct FocusSession: Sendable, Equatable {
  public private(set) var phase: FocusPhase = .idle
  public private(set) var remaining: Duration

  private var duration: Duration
  private let idlePauseAfter: Duration

  public init(duration: Duration = .seconds(1_500), idlePauseAfter: Duration = .seconds(60)) {
    self.duration = duration
    self.idlePauseAfter = idlePauseAfter
    self.remaining = duration
  }

  public mutating func start() {
    remaining = duration
    phase = .running
  }

  /// Updates the configured session duration. An active session restarts its
  /// countdown from the new duration so a settings change cannot leave a
  /// stale partial countdown in effect.
  public mutating func updateDuration(_ duration: Duration) {
    self.duration = max(duration, .zero)
    remaining = self.duration
  }

  public mutating func cancel() {
    remaining = duration
    phase = .idle
  }

  public mutating func advance(by elapsed: Duration, userIdle: Duration) {
    guard phase == .running || phase == .pausedForIdle else { return }
    if userIdle >= idlePauseAfter {
      phase = .pausedForIdle
      return
    }
    if phase == .pausedForIdle { phase = .running }

    remaining -= max(elapsed, .zero)
    if remaining <= .zero {
      remaining = .zero
      phase = .completed
    }
  }
}
