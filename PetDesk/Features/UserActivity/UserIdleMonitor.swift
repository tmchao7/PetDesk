import CoreGraphics
import Foundation

public protocol UserIdleSampling: Sendable {
  func idleDuration() async -> Duration
}

public struct CGEventUserIdleSampler: UserIdleSampling {
  public init() {}

  public func idleDuration() -> Duration {
    guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else { return .zero }
    let seconds = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState,
      eventType: anyInputEvent
    )
    return .milliseconds(Int64(max(seconds, 0) * 1_000))
  }
}

public struct UserIdleMonitor: PetSignalSource {
  private let sampler: any UserIdleSampling
  private let interval: Duration

  public init(
    sampler: any UserIdleSampling = CGEventUserIdleSampler(), interval: Duration = .seconds(1)
  ) {
    self.sampler = sampler
    self.interval = interval
  }

  public func events() -> AsyncStream<PetEvent> {
    let sampler = sampler
    let interval = interval
    return AsyncStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          continuation.yield(.userIdleChanged(await sampler.idleDuration()))
          try? await Task.sleep(for: interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
