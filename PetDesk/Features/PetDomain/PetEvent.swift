import Foundation

public enum ThermalLevel: String, Sendable, Equatable, Codable {
  case nominal
  case fair
  case serious
  case critical
}

public struct SystemMetrics: Sendable, Equatable {
  public let cpuLoad: Double
  public let thermalLevel: ThermalLevel

  public init(cpuLoad: Double, thermalLevel: ThermalLevel) {
    self.cpuLoad = min(max(cpuLoad, 0), 1)
    self.thermalLevel = thermalLevel
  }
}

public enum NotificationSource: String, Sendable, Equatable, Hashable, Codable {
  case wechat
  case qq
}

public enum FocusCommand: Sendable, Equatable {
  case start
  case complete
  case cancel
  case showActivityReminder
  case snoozeActivity
}

public enum PetEvent: Sendable, Equatable {
  case systemMetrics(SystemMetrics)
  case userIdleChanged(Duration)
  case notificationPulse(NotificationSource)
  case focusCommand(FocusCommand)
  case tick(Duration)
}

public protocol PetSignalSource: Sendable {
  func events() -> AsyncStream<PetEvent>
}
