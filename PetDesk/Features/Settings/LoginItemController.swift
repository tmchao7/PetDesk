import Combine
import Foundation
import ServiceManagement

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

@MainActor
final class LoginItemController: ObservableObject {
  @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
  @Published private(set) var errorMessage: String?

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      isEnabled = SMAppService.mainApp.status == .enabled
      errorMessage = nil
    } catch {
      isEnabled = SMAppService.mainApp.status == .enabled
      errorMessage = "Login item could not be updated."
      AppLog.app.error("Login item update failed")
    }
  }
}
