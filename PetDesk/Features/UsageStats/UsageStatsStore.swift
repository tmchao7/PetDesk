import Foundation

/// 使用统计的 JSON 文件持久化（类似 TodoStore）。
public actor UsageStatsStore {
  private let fileManager: FileManager
  private let fileURL: URL

  public init(
    fileManager: FileManager = .default,
    directoryURL: URL? = nil
  ) throws {
    self.fileManager = fileManager
    if let directoryURL {
      self.fileURL = directoryURL.appendingPathComponent("usage-stats.json")
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = applicationSupport.appendingPathComponent("PetDesk", isDirectory: true)
      self.fileURL = directory.appendingPathComponent("usage-stats.json")
    }
  }

  public func loadAll() -> [DayStats] {
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let days = try? JSONDecoder().decode([DayStats].self, from: data)
    else { return [] }
    return days
  }

  /// 合并某一天的统计并写回文件。当天已有数据则累加，否则新增。
  public func upsert(_ day: DayStats) throws {
    var days = loadAll()
    if let index = days.firstIndex(where: { $0.date == day.date }) {
      days[index] = day
    } else {
      days.append(day)
    }
    days.sort { $0.date < $1.date }
    try save(days)
  }

  private func save(_ days: [DayStats]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(days)
    try data.write(to: fileURL, options: .atomic)
  }
}
