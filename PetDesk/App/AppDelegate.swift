import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let environment = AppEnvironment()
  private var petWindowController: PetWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--reset-window-position") {
      ScreenPositionStore().reset()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    environment.start()
    petWindowController = PetWindowController(environment: environment)
    petWindowController?.showPet()
    applyLaunchArguments(arguments)
  }

  func applicationWillTerminate(_ notification: Notification) {
    environment.stop()
  }

  func togglePet() {
    petWindowController?.toggleVisibility()
  }

  private func applyLaunchArguments(_ arguments: [String]) {
    if let index = arguments.firstIndex(of: "--demo-state"), arguments.indices.contains(index + 1) {
      environment.applyDemoState(arguments[index + 1])
    }
    if let index = arguments.firstIndex(of: "--fake-notification"),
      arguments.indices.contains(index + 1)
    {
      let value = arguments[index + 1]
      environment.injectNotification(value == "qq" ? .qq : .wechat)
    }
  }
}
