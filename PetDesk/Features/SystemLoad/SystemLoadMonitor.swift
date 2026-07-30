import Foundation

public struct SystemLoadMonitor: PetSignalSource {
  private let sampler: any CPUSampling
  private let interval: Duration

  public init(sampler: any CPUSampling = MachCPUSampler(), interval: Duration = .seconds(1)) {
    self.sampler = sampler
    self.interval = interval
  }

  public func events() -> AsyncStream<PetEvent> {
    let sampler = sampler
    let interval = interval
    return AsyncStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          if let cpuLoad = try? await sampler.sample() {
            continuation.yield(
              .systemMetrics(
                SystemMetrics(cpuLoad: cpuLoad, thermalLevel: Self.thermalLevel)
              )
            )
          }
          try? await Task.sleep(for: interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static var thermalLevel: ThermalLevel {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .fair
    }
  }
}
