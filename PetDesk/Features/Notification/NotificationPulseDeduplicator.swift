import Foundation

public struct NotificationPulseDeduplicator: Sendable {
  private let cooldown: Duration
  private var lastEmission: [NotificationSource: Duration] = [:]

  public init(cooldown: Duration = .seconds(3)) {
    self.cooldown = cooldown
  }

  public mutating func shouldEmit(source: NotificationSource, at elapsed: Duration) -> Bool {
    if let previous = lastEmission[source], elapsed - previous < cooldown {
      return false
    }
    lastEmission[source] = elapsed
    return true
  }
}

public enum NotificationUnsupportedReason: String, Sendable, Equatable, Codable {
  case sourceApplicationUnavailable
}

public enum NotificationCapability: Sendable, Equatable {
  case unsupported(NotificationUnsupportedReason)
  case available
}
