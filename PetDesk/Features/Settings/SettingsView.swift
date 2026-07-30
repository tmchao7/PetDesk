import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @ObservedObject var environment: AppEnvironment
  @StateObject private var loginItem = LoginItemController()
  @State private var showingImporter = false

  var body: some View {
    Form {
      Section("Avatar") {
        HStack(spacing: 14) {
          AvatarView(image: environment.avatarImage)
            .frame(width: 64, height: 64)
          Button("Choose Image", systemImage: "photo") { showingImporter = true }
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
      Task { await environment.importAvatar(from: url) }
    }
  }

  private var notificationStatus: String {
    switch environment.notificationCapability {
    case .available: "Available"
    case .unsupported: "Unsupported on this system"
    }
  }
}
