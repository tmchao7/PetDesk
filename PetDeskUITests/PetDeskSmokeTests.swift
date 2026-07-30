import XCTest

final class PetDeskSmokeTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testPetAppearsInDemoState() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "working"]
    app.launch()

    XCTAssertTrue(app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5))
  }

  func testFakeNotificationStillLaunchesWithoutAccessibilityPermission() {
    let app = XCUIApplication()
    app.launchArguments = ["--fake-notification", "wechat"]
    app.launch()

    XCTAssertTrue(app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5))
  }
}
