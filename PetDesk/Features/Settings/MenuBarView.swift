import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var environment: AppEnvironment
  let togglePet: () -> Void

  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Show or Hide Pet", systemImage: "eye") { togglePet() }

    if environment.focusSession.phase == .running
      || environment.focusSession.phase == .pausedForIdle
    {
      Button("Cancel Focus", systemImage: "xmark.circle") { environment.cancelFocus() }
    } else {
      Button("Start 25-minute Focus", systemImage: "timer") { environment.startFocus() }
    }

    Toggle("Quiet Mode", systemImage: "speaker.slash", isOn: $environment.quietMode)

    Divider()

    Button("Diagnostics", systemImage: "waveform.path.ecg") {
      openWindow(id: "diagnostics")
    }
    Button("Settings", systemImage: "gearshape") { openSettings() }

    Divider()

    Button("Quit PetDesk", systemImage: "power") { NSApplication.shared.terminate(nil) }
  }
}
