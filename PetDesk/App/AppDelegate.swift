import AppKit
import SwiftUI

/// 构建标记：用于从磁盘/设置界面确认运行的是新代码。
enum AppBuildMarker {
  static let tag = "pose-import-v2"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let environment = AppEnvironment()
  private var petWindowController: PetWindowController?
  private var shelfPanel: DragShelfPanel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--reset-window-position") {
      ScreenPositionStore().reset()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    environment.start()
    environment.loadShelfItems()
    writeBuildMarker()
    petWindowController = PetWindowController(environment: environment)
    petWindowController?.showPet()
    setupShelfPanel()
    applyLaunchArguments(arguments)
  }

  /// 创建拖拽缓存托盘面板（拖入文件时由桌宠窗口回调打开）。
  private func setupShelfPanel() {
    let panel = DragShelfPanel(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 340)
    )
    let hosting = NSHostingView(rootView: DragShelfView(environment: environment))
    panel.contentView = hosting
    panel.installDragHandle(contentHeight: 340)
    panel.onFilesDropped = { [weak self] urls in
      self?.environment.addShelfItems(urls)
      self?.showShelf()
    }
    panel.center()
    environment.shelfPanel = panel
    shelfPanel = panel
  }

  /// 显示/隐藏暂存托盘（状态栏入口）。
  func toggleShelf() {
    guard let panel = shelfPanel else { return }
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      panel.orderFrontRegardless()
      panel.makeKey()
    }
  }

  /// 拖入文件时自动弹出托盘（不抢焦点）。
  func showShelf() {
    guard let panel = shelfPanel else { return }
    panel.orderFrontRegardless()
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
