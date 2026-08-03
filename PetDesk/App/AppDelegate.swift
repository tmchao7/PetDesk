import AppKit

/// 构建标记：用于从磁盘/设置界面确认运行的是新代码。
enum AppBuildMarker {
  static let tag = "pose-import-v2"
}

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
    writeBuildMarker()
    petWindowController = PetWindowController(environment: environment)
    petWindowController?.showPet()
    applyLaunchArguments(arguments)
  }

  /// 每次启动把构建标记写入应用数据目录，便于确认当前运行的是新构建。
  private func writeBuildMarker() {
    guard
      let base = try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    else { return }
    let directory = base.appendingPathComponent("PetDesk", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("app-build.txt")
    try? "\(AppBuildMarker.tag) \(Date())".write(to: url, atomically: true, encoding: .utf8)
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
