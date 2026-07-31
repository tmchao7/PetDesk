import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var environment: AppEnvironment
  let togglePet: () -> Void
  let openDiagnostics: () -> Void

  var body: some View {
    Button("显示/隐藏桌宠", systemImage: "eye") {
      dismissThen { togglePet() }
    }

    if environment.focusSession.phase == .running
      || environment.focusSession.phase == .pausedForIdle
    {
      Button("取消专注", systemImage: "xmark.circle") { environment.cancelFocus() }
    } else {
      Button("开始 25 分钟专注", systemImage: "timer") { environment.startFocus() }
    }

    Toggle("静音模式", systemImage: "speaker.slash", isOn: $environment.quietMode)

    Divider()

    Button("待办事项", systemImage: "checklist") {
      dismissThen { environment.openTodoWindow?() }
    }
    Button("诊断日志", systemImage: "waveform.path.ecg") {
      dismissThen { openDiagnostics() }
    }
    SettingsLink { Label("设置", systemImage: "gearshape") }

    Divider()

    Button("退出 PetDesk", systemImage: "power") { NSApplication.shared.terminate(nil) }
  }

  /// Menu bar apps use `.accessory` activation policy, so macOS refuses to
  /// bring their windows to the front.  Temporarily switch to `.regular` (Dock
  /// icon appears briefly), activate, perform the action, then the window's
  /// own `.onDisappear` switches back to `.accessory`.
  private func dismissThen(_ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      action()
    }
  }
}
