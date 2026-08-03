import SwiftUI
import UniformTypeIdentifiers

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @StateObject private var loginItem = LoginItemController()
  @State private var showingImporter = false
  @State private var showingSpritesheetImporter = false
  @State private var showingEditor = false
  @State private var poseImportTarget: AnimationRow?
  @State private var poseImportMessage: String?

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
          "支持 1536×1664 标准图，或任意 1:1 方形 8×8 网格（如 1024×1024，自动规整重排）；"
            + "纯色背景会自动抠底。行序为 idle / walking / running / working / drinking / "
            + "sleeping / happy / surprised（PNG/WebP）。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Divider()
        poseRow("专注姿势", row: .working, systemImage: "timer")
        poseRow("摸鱼姿势", row: .drinking, systemImage: "cup.and.saucer.fill")
        poseRow("休息姿势", row: .sleeping, systemImage: "moon.zzz.fill")
        Text(
          "每个状态一张姿势图（PNG/WebP，纯色或透明背景，自动抠底）："
            + "导入后该状态的动画使用这张姿势图，其余状态仍用默认形象；"
            + "一行动画帧由应用自动生成，无需提供多帧。"
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
    .frame(width: 480, height: 580)
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
    .fileImporter(
      isPresented: Binding(
        get: { poseImportTarget != nil },
        set: { if !$0 { poseImportTarget = nil } }
      ),
      allowedContentTypes: [.png, .webP],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first, let row = poseImportTarget
      else {
        poseImportTarget = nil
        return
      }
      poseImportTarget = nil
      Task {
        let message = await environment.importPose(row: row, from: url)
        if let message {
          poseImportMessage = message
        } else {
          poseImportMessage = "已导入「\(poseName(for: row))」。"
        }
      }
    }
    .alert(
      "导入姿势图",
      isPresented: Binding(
        get: { poseImportMessage != nil },
        set: { if !$0 { poseImportMessage = nil } }
      )
    ) {
      Button("好") { poseImportMessage = nil }
    } message: {
      Text(poseImportMessage ?? "")
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

  @ViewBuilder
  private func poseRow(_ label: String, row: AnimationRow, systemImage: String) -> some View {
    HStack {
      if let thumbnail = environment.customPoseImages[row] {
        Image(nsImage: thumbnail)
          .resizable()
          .frame(width: 36, height: 39)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      Label(label, systemImage: systemImage)
      Spacer()
      if environment.customPoseRows.contains(row) {
        Button("清除") {
          Task {
            let message = await environment.clearPose(row: row)
            if let message {
              poseImportMessage = message
            } else {
              poseImportMessage = "已清除「\(poseName(for: row))」。"
            }
          }
        }
        .font(.caption)
      }
      Button(
        environment.customPoseRows.contains(row) ? "更换…" : "导入…",
        systemImage: "square.and.arrow.down"
      ) {
        poseImportTarget = row
      }
      .font(.caption)
    }
  }

  private func poseName(for row: AnimationRow) -> String {
    switch row {
    case .working: "专注姿势"
    case .drinking: "摸鱼姿势"
    case .sleeping: "休息姿势"
    default: "姿势"
    }
  }
}
