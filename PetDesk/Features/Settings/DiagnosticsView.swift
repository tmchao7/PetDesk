import AppKit
import SwiftUI

struct DiagnosticsView: View {
  @ObservedObject var environment: AppEnvironment

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Diagnostics").font(.headline)
          Text(statusLine).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Copy", systemImage: "doc.on.doc") { copyReport() }
      }
      .padding(16)

      Divider()

      List(environment.diagnostics.lines) { line in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(line.timestamp, style: .time)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Text(line.category)
            .font(.caption.weight(.semibold))
            .frame(width: 88, alignment: .leading)
          Text(line.message).font(.caption.monospaced())
        }
      }
    }
    .frame(minWidth: 660, minHeight: 420)
  }

  private var statusLine: String {
    "\(environment.snapshot.baseState.rawValue) · CPU \(Int(environment.snapshot.averageCPU * 100))%"
  }

  private func copyReport() {
    let report = environment.diagnostics.encodedReport(
      snapshot: environment.snapshot,
      notificationCapability: environment.notificationCapability,
      windowFrame: environment.petWindowFrame
    )
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
  }
}
