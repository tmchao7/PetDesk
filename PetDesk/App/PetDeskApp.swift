import SwiftUI

@main
struct PetDeskApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("PetDesk", systemImage: "face.smiling") {
      MenuBarView(environment: appDelegate.environment) {
        appDelegate.togglePet()
      }
    }

    Settings {
      SettingsView(environment: appDelegate.environment)
    }

    Window("PetDesk Diagnostics", id: "diagnostics") {
      DiagnosticsView(environment: appDelegate.environment)
    }
    .defaultSize(width: 700, height: 460)
  }
}
