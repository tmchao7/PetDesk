import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @StateObject private var loginItem = LoginItemController()
  @State private var showingImporter = false
  @State private var showingSpritesheetImporter = false
  @State private var showingEditor = false

  var body: some View {
    Form {
      Section("头像") {
        HStack(spacing: 14) {
          AvatarView(image: environment.avatarImage, displayMode: environment.avatarDisplayMode)
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 6) {
            Button("选择图片", systemImage: "photo") { showingImporter = true }
            if environment.avatarImage != nil {
              Button("恢复默认", systemImage: "arrow.counterclockwise") {
                Task { await environment.resetAvatar() }
              }
              .font(.caption)
            }
          }
        }
        if let avatarError = environment.avatarError {
          Text(avatarError).foregroundStyle(.red)
        }
        Button("导入精灵图…", systemImage: "square.grid.3x3") {
          showingSpritesheetImporter = true
        }
        Text("支持 PNG、JPEG 或 HEIC，最大 20 MB。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(
          "用在线 AI（豆包/GPT/Gemini 等）生成整张精灵图后上传：1536×1664（8 行 × 8 列，"
            + "每格 192×208），行序为 idle / walking / running / working / drinking / sleeping / "
            + "happy / surprised，需要透明背景（PNG/WebP）。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("外观") {
        Picker("桌宠大小", selection: $environment.petScale) {
          Text("小").tag(0.75)
          Text("中").tag(1.0)
          Text("大").tag(1.25)
        }
        .pickerStyle(.segmented)
      }

      Section("统计") {
        Button("查看使用统计", systemImage: "chart.bar.fill") {
          environment.openStatsWindow?()
        }
      }

      Section("行为") {
        Toggle(
          "登录时启动",
          isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
          )
        )
        if let errorMessage = loginItem.errorMessage {
          Text(errorMessage).foregroundStyle(.red)
        }
      }

      Section("集成") {
        LabeledContent("微信 / QQ 通知") {
          Text(notificationStatus)
            .foregroundStyle(.secondary)
        }
        Text("PetDesk 不会读取消息内容或联系人姓名。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 500)
    .onAppear {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }
    .onDisappear {
      NSApp.setActivationPolicy(.accessory)
    }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.png, .jpeg, .heic],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task {
        await environment.loadSourceForEdit(from: url)
        if environment.avatarSourceImage != nil {
          showingEditor = true
        }
      }
    }
    .fileImporter(
      isPresented: $showingSpritesheetImporter,
      allowedContentTypes: [.png, .webP],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task {
        await environment.importSpritesheet(from: url)
      }
    }
    .sheet(isPresented: $showingEditor) {
      editorSheet
    }
  }

  @ViewBuilder
  private var editorSheet: some View {
    if let sourceImage = environment.avatarSourceImage {
      let nsImage = NSImage(
        cgImage: sourceImage,
        size: NSSize(width: sourceImage.width, height: sourceImage.height))
      AvatarEditorView(
        sourceImage: nsImage,
        initialDisplayMode: environment.avatarDisplayMode,
        onConfirm: { cropped, displayMode in
          showingEditor = false
          environment.avatarDisplayMode = displayMode
          Task { await environment.saveCroppedAvatar(cropped) }
        },
        onCancel: {
          showingEditor = false
        }
      )
    }
  }

  private var notificationStatus: String {
    switch environment.notificationCapability {
    case .available: "可用"
    case .unsupported: "当前系统不支持"
    }
  }
}
