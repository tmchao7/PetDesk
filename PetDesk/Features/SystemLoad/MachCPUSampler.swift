import Darwin
import Foundation

public enum CPUSamplingError: Error, Sendable {
  case hostStatisticsFailed(kern_return_t)
}

public protocol CPUSampling: Sendable {
  func sample() async throws -> Double?
}

public actor MachCPUSampler: CPUSampling {
  private var calculator = CPULoadCalculator()

  public init() {}

  public func sample() throws -> Double? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      throw CPUSamplingError.hostStatisticsFailed(result)
    }

    let ticks = CPUTicks(
      user: UInt64(info.cpu_ticks.0),
      system: UInt64(info.cpu_ticks.1),
      idle: UInt64(info.cpu_ticks.2),
      nice: UInt64(info.cpu_ticks.3)
    )
    return calculator.record(ticks)
  }
}
