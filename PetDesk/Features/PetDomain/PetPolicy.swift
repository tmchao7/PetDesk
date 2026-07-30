import Foundation

public struct PetPolicy: Sendable, Equatable {
  public var coolThreshold = 0.20
  public var busyThreshold = 0.60
  public var hotThreshold = 0.80
  public var hysteresis = 0.05
  public var stateDwell: Duration = .seconds(5)
  public var idleSleepAfter: Duration = .seconds(300)
  public var notificationDuration: Duration = .milliseconds(2_500)
  public var sampleCount = 10

  public init() {}
}
