import Foundation

public struct CPUTicks: Sendable, Equatable {
  public let user: UInt64
  public let system: UInt64
  public let idle: UInt64
  public let nice: UInt64

  public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
    self.user = user
    self.system = system
    self.idle = idle
    self.nice = nice
  }

  var total: UInt64 { user + system + idle + nice }
  var busy: UInt64 { user + system + nice }
}

public struct CPULoadCalculator: Sendable {
  private var previous: CPUTicks?

  public init() {}

  public mutating func record(_ ticks: CPUTicks) -> Double? {
    defer { previous = ticks }
    guard let previous,
      ticks.total >= previous.total,
      ticks.busy >= previous.busy
    else { return nil }

    let totalDelta = ticks.total - previous.total
    guard totalDelta > 0 else { return nil }
    let busyDelta = ticks.busy - previous.busy
    return min(max(Double(busyDelta) / Double(totalDelta), 0), 1)
  }
}
