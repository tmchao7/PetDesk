import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @StateObject private var loginItem = LoginItemController()
  @State private var showingImporter = false
  @State private var showingEditor = false

  var body: some View {
    Form {
      Section("Avatar") {
        HStack(spacing: 14) {
          AvatarView(image: environment.avatarImage, displayMode: environment.avatarDisplayMode)
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 6) {
            Button("Choose Image", systemImage: "photo") { showingImporter = true }
            if environment.avatarImage != nil {
              Button("Reset to Default", systemImage: "arrow.counterclockwise") {
                Task { await environment.resetAvatar() }
              }
              .font(.caption)
            }
          }
        }
        if let avatarError = environment.avatarError {
          Text(avatarError).foregroundStyle(.red)
        }
        Text("PNG, JPEG, or HEIC. Maximum 20 MB.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Behavior") {
        Toggle("Quiet mode", isOn: $environment.quietMode)
        Toggle(
          "Open at login",
          isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
          )
        )
        if let errorMessage = loginItem.errorMessage {
          Text(errorMessage).foregroundStyle(.red)
        }
      }

      Section("Integrations") {
        LabeledContent("WeChat / QQ notifications") {
          Text(notificationStatus)
            .foregroundStyle(.secondary)
        }
        Text("PetDesk never reads message text or contact names.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 430)
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
    case .available: "Available"
    case .unsupported: "Unsupported on this system"
    }
  }
}
