import Foundation

/// 每日使用统计：专注 / 摸鱼 / 休息 时长（秒）。
public struct DayStats: Sendable, Equatable, Codable {
  /// 日期键，格式 "yyyy-MM-dd"。
  public let date: String
  public var focusSeconds: Int
  public var teaSeconds: Int
  public var sleepSeconds: Int

  public init(date: String, focusSeconds: Int = 0, teaSeconds: Int = 0, sleepSeconds: Int = 0) {
    self.date = date
    self.focusSeconds = focusSeconds
    self.teaSeconds = teaSeconds
    self.sleepSeconds = sleepSeconds
  }

  public var totalSeconds: Int {
    focusSeconds + teaSeconds + sleepSeconds
  }

  /// DateFormatter 创建开销大（加载 locale 数据），而 todayKey 每秒都会被
  /// 调用（统计累计），必须复用共享实例。
  private static let keyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  public static func todayKey(calendar: Calendar = .current, now: Date = Date()) -> String {
    keyFormatter.calendar = calendar
    return keyFormatter.string(from: now)
  }
}
