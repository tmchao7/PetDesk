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

    // After tapping, the bubble with quick actions should appear.
    // The action labels are rendered as custom gesture views, so match
    // them as generic elements rather than buttons.
    let bubble = app.descendants(matching: .any).matching(identifier: "pet.bubble").firstMatch
    let focusLabel = app.descendants(matching: .any)["专注"]
    let slackLabel = app.descendants(matching: .any)["摸鱼"]
    let relaxLabel = app.descendants(matching: .any)["放松"]

    let appeared =
      bubble.waitForExistence(timeout: 2)
      || focusLabel.waitForExistence(timeout: 2)
      || slackLabel.waitForExistence(timeout: 2)
      || relaxLabel.waitForExistence(timeout: 2)
    if !appeared {
      print("DEBUG UI TREE AFTER TAP:\n\(app.debugDescription)")
    }
    XCTAssertTrue(appeared, "bubble or quick actions should appear after tapping pet")

    // Click the 专注 action in the bubble, then verify the bubble dismisses
    // (startFocus() hides the quick actions).
    let focusCenter = focusLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    focusCenter.click()
    let bubbleGone = bubble.waitForNonExistence(timeout: 2)
    if !bubbleGone {
      print("DEBUG UI TREE AFTER FOCUS CLICK:\n\(app.debugDescription)")
    }
    XCTAssertTrue(bubbleGone, "bubble should dismiss after tapping 专注")
  }
}
