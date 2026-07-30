import AppKit
import Combine
import Foundation

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct DiagnosticLine: Identifiable, Codable, Sendable {
  let id: UUID
  let timestamp: Date
  let category: String
  let message: String

  init(category: String, message: String) {
    self.id = UUID()
    self.timestamp = Date()
    self.category = category
    self.message = message
  }
}

@MainActor
final class DiagnosticRecorder: ObservableObject {
  @Published private(set) var lines: [DiagnosticLine] = []
  private var buffer = RingBuffer<DiagnosticLine>(capacity: 200)

  func record(category: String, message: String) {
    buffer.append(DiagnosticLine(category: category, message: message))
    lines = buffer.values
  }

  func encodedReport(
    snapshot: PetSnapshot,
    notificationCapability: NotificationCapability,
    windowFrame: CGRect?
  ) -> String {
    let report = DiagnosticReport(
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "development",
      systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      baseState: snapshot.baseState.rawValue,
      transientState: String(describing: snapshot.transientState),
      averageCPU: snapshot.averageCPU,
      notificationCapability: String(describing: notificationCapability),
      windowFrame: windowFrame.map(NSStringFromRect),
      events: lines
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(report), let string = String(data: data, encoding: .utf8)
    else {
      return "{\"error\":\"diagnostics-encoding-failed\"}"
    }
    return string
  }
}

private struct DiagnosticReport: Codable {
  let appVersion: String
  let systemVersion: String
  let baseState: String
  let transientState: String
  let averageCPU: Double
  let notificationCapability: String
  let windowFrame: String?
  let events: [DiagnosticLine]
}
