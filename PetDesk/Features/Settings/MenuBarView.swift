import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var environment: AppEnvironment
  let togglePet: () -> Void

  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("显示/隐藏桌宠", systemImage: "eye") { togglePet() }

    if environment.focusSession.phase == .running
      || environment.focusSession.phase == .pausedForIdle
    {
      Button("取消专注", systemImage: "xmark.circle") { environment.cancelFocus() }
    } else {
      Button("开始 25 分钟专注", systemImage: "timer") { environment.startFocus() }
    }

    Toggle("静音模式", systemImage: "speaker.slash", isOn: $environment.quietMode)

    Divider()

    Button("诊断日志", systemImage: "waveform.path.ecg") {
      openWindow(id: "diagnostics")
    }
    Button("设置", systemImage: "gearshape") { openSettings() }

    Divider()

    Button("退出 PetDesk", systemImage: "power") { NSApplication.shared.terminate(nil) }
  }
}
