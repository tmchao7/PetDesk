import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// 使用统计面板：按天查看 专注/摸鱼/休息 时长。
struct StatsView: View {
  @ObservedObject var environment: AppEnvironment

  /// DateFormatter 创建开销大，全部用共享实例（body 每次求值曾分配约 21 个）。
  private static let dateKeyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
  private static let displayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "M月d日 EEEE"
    return formatter
  }()

  /// 最近 7 天（含今天）。
  private var recentDays: [String] {
    let calendar = Calendar.current
    let today = Date()
    return (0..<7).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
      return Self.dateKeyFormatter.string(from: date)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("使用统计", systemImage: "chart.bar.fill")
        .font(.headline)

      // 最近 7 天列表
      ScrollView {
        VStack(spacing: 10) {
          ForEach(recentDays, id: \.self) { dateKey in
            dayRow(dateKey: dateKey)
          }
        }
        .padding(.vertical, 4)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(width: 360, height: 420)
    .onAppear {
      environment.auxiliaryWindowDidAppear()
    }
    .onDisappear {
      environment.auxiliaryWindowDidDisappear()
    }
  }

  private func dayRow(dateKey: String) -> some View {
    let day = environment.usageStatsByDay[dateKey] ?? DayStats(date: dateKey)
    let isToday = dateKey == DayStats.todayKey()
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(displayDate(dateKey))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isToday ? .primary : .secondary)
        if isToday {
          Text("今天")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
        }
        Spacer()
        Text(formatDuration(day.totalSeconds))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }

      barRow(label: "专注", seconds: day.focusSeconds, total: day.totalSeconds, color: .orange)
      barRow(label: "摸鱼", seconds: day.teaSeconds, total: day.totalSeconds, color: .green)
      barRow(label: "休息", seconds: day.sleepSeconds, total: day.totalSeconds, color: .indigo)
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  private func barRow(label: String, seconds: Int, total: Int, color: Color) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 32, alignment: .leading)

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3)
            .fill(.quaternary)
          if total > 0 {
            RoundedRectangle(cornerRadius: 3)
              .fill(color)
              .frame(width: max(4, geometry.size.width * CGFloat(seconds) / CGFloat(total)))
          }
        }
      }
      .frame(height: 8)

      Text(formatDuration(seconds))
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .frame(width: 64, alignment: .trailing)
    }
  }

  private func displayDate(_ dateKey: String) -> String {
    guard let date = Self.dateKeyFormatter.date(from: dateKey) else { return dateKey }
    return Self.displayFormatter.string(from: date)
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}
