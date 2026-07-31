import SwiftUI

@main
struct PetDeskApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    MenuBarExtra("PetDesk", systemImage: "face.smiling") {
      // Wire the App-level environment actions into AppEnvironment so deep
      // views (e.g. context menus) can open Settings / Diagnostics even
      // though @Environment is unavailable outside the scene hierarchy.
      // This runs every time the menu content is evaluated, which is
      // guaranteed before the user interacts with the context menu.
      let _ = wireRelays()

      MenuBarView(
        environment: appDelegate.environment,
        togglePet: { appDelegate.togglePet() },
        openDiagnostics: {
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
          openWindow(id: "diagnostics")
        }
      )
    }

    Settings {
      SettingsView(environment: appDelegate.environment)
    }

    Window("PetDesk Diagnostics", id: "diagnostics") {
      DiagnosticsView(environment: appDelegate.environment)
    }
    .defaultSize(width: 700, height: 460)
  }

  /// Capture `openSettings` and `openWindow` from the App's environment and
  /// store them on `AppEnvironment` so context menus (which lack a SwiftUI
  /// environment) can open Settings and Diagnostics windows.
  private func wireRelays() {
    appDelegate.environment.openSettings = { [openSettings] in
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      openSettings()
    }
    appDelegate.environment.openDiagnosticsWindow = { [openWindow] in
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "diagnostics")
    }
    appDelegate.environment.hidePet = { [weak appDelegate] in
      appDelegate?.togglePet()
    }
  }
}
