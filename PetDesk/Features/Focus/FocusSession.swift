import Foundation

public enum FocusPhase: String, Sendable, Equatable, Codable {
  case idle
  case running
  case paused
  case pausedForIdle
  case completed
}

public struct FocusSession: Sendable, Equatable {
  public private(set) var phase: FocusPhase = .idle
  public private(set) var remaining: Duration

  private let duration: Duration
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

  public mutating func pause() {
    guard phase == .running else { return }
    phase = .paused
  }

  public mutating func resume() {
    guard phase == .paused || phase == .pausedForIdle else { return }
    phase = .running
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
