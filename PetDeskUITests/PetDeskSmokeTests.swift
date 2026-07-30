import XCTest

final class PetDeskSmokeTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPetAppearsInDemoState() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "working"]
    app.launch()

    XCTAssertTrue(app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testFakeNotificationStillLaunchesWithoutAccessibilityPermission() {
    let app = XCUIApplication()
    app.launchArguments = ["--fake-notification", "wechat"]
    app.launch()

    XCTAssertTrue(app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPetAppearsInSleepingState() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "sleeping"]
    app.launch()

    XCTAssertTrue(
      app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5),
      "pet avatar should appear in sleeping state")
  }

  @MainActor
  func testPetAppearsInFocusingState() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "focusing"]
    app.launch()

    XCTAssertTrue(
      app.descendants(matching: .any)["pet.avatar"].waitForExistence(timeout: 5),
      "pet avatar should appear in focusing state")
  }

  @MainActor
  func testPetAvatarIsHittable() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "working"]
    app.launch()

    let avatar = app.descendants(matching: .any)["pet.avatar"]
    XCTAssertTrue(avatar.waitForExistence(timeout: 5))
    XCTAssertTrue(avatar.isHittable, "pet avatar should be hittable for click-through")
  }

  @MainActor
  func testQuickActionsAppearOnTap() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "working"]
    app.launch()

    let avatar = app.descendants(matching: .any)["pet.avatar"]
    XCTAssertTrue(avatar.waitForExistence(timeout: 5))
    avatar.tap()

    // After tapping, a bubble or quick actions should appear
    let bubble = app.descendants(matching: .any).matching(identifier: "pet.bubble").firstMatch
    let focusButton = app.buttons["专注"]
    let quietButton = app.buttons["静音"]

    let appeared =
      bubble.waitForExistence(timeout: 2)
      || focusButton.waitForExistence(timeout: 2)
      || quietButton.waitForExistence(timeout: 2)
    XCTAssertTrue(appeared, "bubble or quick actions should appear after tapping pet")
  }
}
