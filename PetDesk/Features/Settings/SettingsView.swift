import SwiftUI
import UniformTypeIdentifiers

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @StateObject private var loginItem = LoginItemController()
  /// 唯一的文件导入通道：不同按钮先写入 pendingFileImport 再置 showingFileImporter。
  /// 不要用“target != nil”推导 isPresented —— fileImporter 在完成回调执行前就会把
  /// isPresented 置回 false，派生绑定会把目标清空，导致回调静默丢失（macOS 已知行为，
  /// 见 Apple 文档 fileImporter(isPresented:...)）。同视图也只挂一个 fileImporter，
  /// 多个 modifier 在 macOS 上可能只有第一个生效。
  @State private var showingFileImporter = false
  @State private var pendingFileImport: FileImportMode?
  @State private var showingEditor = false
  @State private var poseImportMessage: String?

  var body: some View {
    Form {
      Section("头像") {
        HStack(spacing: 14) {
          AvatarView(image: environment.avatarImage, displayMode: environment.avatarDisplayMode)
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 6) {
            Button("选择图片", systemImage: "photo") {
              pendingFileImport = .avatarSource
              showingFileImporter = true
            }
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
        Text("支持 PNG、JPEG 或 HEIC，最大 20 MB。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          poseRow("专注姿势", row: .working, systemImage: "timer")
          poseRow("摸鱼姿势", row: .drinking, systemImage: "cup.and.saucer.fill")
          poseRow("休息姿势", row: .sleeping, systemImage: "moon.zzz.fill")
          Text(
            "每个状态可导入姿势图（PNG/WebP，纯色或透明背景，自动抠底）："
              + "专注支持一次多选最多 8 张动作帧，按序循环播放、速度随 CPU 变化；"
              + "其余状态单张即可，未设置的状态仍用默认形象。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("外观") {
        Picker("桌宠大小", selection: $environment.petScale) {
          Text("小").tag(0.75)
          Text("中").tag(1.0)
          Text("大").tag(1.25)
        }
        .pickerStyle(.segmented)

        // 动画速度：CPU 负载变化时精灵动作的快慢倍率。
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("动画速度")
            Spacer()
            Text("\(environment.animationSpeedMultiplier, specifier: "%.1f")×")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(
            value: $environment.animationSpeedMultiplier,
            in: 0.25...4.0,
            step: 0.25
          )
          Text("CPU 越高精灵动得越快；调大倍率让动作更灵敏。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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

      Section("状态时长提醒") {
        Stepper(
          "单次提示时长：\(environment.reminderDisplaySeconds) 秒",
          value: $environment.reminderDisplaySeconds,
          in: 1...120
        )
        ReminderSettingRow(
          title: "专注",
          minutes: $environment.focusDurationMinutes,
          message: $environment.focusReminderMessage,
          previewText: environment.reminderText(
            for: .focusing, minutes: environment.focusDurationMinutes)
        )
        ReminderSettingRow(
          title: "摸鱼",
          minutes: $environment.slackDurationMinutes,
          message: $environment.slackReminderMessage,
          previewText: environment.reminderText(
            for: .drinkingTea, minutes: environment.slackDurationMinutes)
        )
        ReminderSettingRow(
          title: "放松",
          minutes: $environment.relaxDurationMinutes,
          message: $environment.relaxReminderMessage,
          previewText: environment.reminderText(
            for: .sleeping, minutes: environment.relaxDurationMinutes)
        )
        Text(
          "状态持续达到设定时长后，桌宠会以气泡提醒（仅提醒，不自动切换状态）。"
            + "消息支持 {minutes} 占位符，显示实际连续分钟数。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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

      Section("关于") {
        Text("构建：\(AppBuildMarker.tag)（含逐行姿势导入）")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 880)
    .onAppear {
      environment.auxiliaryWindowDidAppear()
    }
    .onDisappear {
      environment.auxiliaryWindowDidDisappear()
    }
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: pendingFileImport?.allowedContentTypes ?? [],
      allowsMultipleSelection: pendingFileImport?.allowsMultipleSelection ?? false,
      onCompletion: { result in
        // 完成回调执行时 isPresented 已为 false，但 pendingFileImport 是独立状态，
        // 不会随弹窗关闭被清空，因此这里仍能拿到用户点的是哪一行。
        defer { pendingFileImport = nil }
        guard case .success(let urls) = result else { return }
        switch pendingFileImport {
        case .avatarSource:
          guard let url = urls.first else { return }
          Task {
            await environment.loadSourceForEdit(from: url)
            if environment.avatarSourceImage != nil {
              showingEditor = true
            }
          }
        case .pose(let row):
          Task {
            let message = await environment.importPose(row: row, from: urls)
            if let message {
              poseImportMessage = message
            } else {
              poseImportMessage =
                urls.count > 1
                ? "已导入「\(poseName(for: row))」\(urls.count) 帧。"
                : "已导入「\(poseName(for: row))」。"
            }
          }
        case nil:
          poseImportMessage = "导入未完成，请重试。"
        }
      },
      onCancellation: {
        pendingFileImport = nil
      }
    )
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
          environment.cancelAvatarEdit()
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
      if let thumbnails = environment.customPoseImages[row] {
        if let thumbnail = thumbnails.first {
          Image(nsImage: thumbnail)
            .resizable()
            .frame(width: 36, height: 39)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        if thumbnails.count > 1 {
          Text("×\(thumbnails.count)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
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
        pendingFileImport = .pose(row)
        showingFileImporter = true
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

/// 文件导入通道的唯一分发模式：一个 fileImporter 处理所有导入，
/// 避免 macOS 上同视图多个 fileImporter 只生效第一个的已知缺陷。
private enum FileImportMode {
  case avatarSource
  case pose(AnimationRow)

  var allowedContentTypes: [UTType] {
    switch self {
    case .avatarSource: [.png, .jpeg, .heic]
    case .pose: [.png, .webP]
    }
  }

  /// 姿势导入支持多选（专注可一次导入最多 8 帧动作帧）；头像单选。
  var allowsMultipleSelection: Bool {
    switch self {
    case .avatarSource: false
    case .pose: true
    }
  }
}

/// 单个状态的时长提醒设置行：时长调节 + 消息 DIY + 实时样式预览。
private struct ReminderSettingRow: View {
  let title: String
  @Binding var minutes: Int
  @Binding var message: String
  let previewText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Stepper("\(title)提醒：\(minutes) 分钟", value: $minutes, in: 1...180)
      TextField("\(title)提醒消息", text: $message)
        .textFieldStyle(.roundedBorder)
      HStack(alignment: .center, spacing: 10) {
        Text("预览")
          .font(.caption)
          .foregroundStyle(.secondary)
        ReminderPreviewView(text: previewText)
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 6)
  }
}
