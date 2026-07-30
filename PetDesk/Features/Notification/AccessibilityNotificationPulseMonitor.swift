import Foundation

public struct AccessibilityNotificationPulseMonitor: PetSignalSource {
  public let capability: NotificationCapability

  public init(capability: NotificationCapability = .unsupported(.sourceApplicationUnavailable)) {
    self.capability = capability
  }

  public func events() -> AsyncStream<PetEvent> {
    AsyncStream { continuation in continuation.finish() }
  }
}
