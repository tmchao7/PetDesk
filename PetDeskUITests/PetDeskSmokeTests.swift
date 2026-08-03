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

    // 逐个断言（不用 OR 链）：任一元素缺失即失败，避免"只出现气泡、
    // 动作标签不存在"的假阳性通过。
    XCTAssertTrue(bubble.waitForExistence(timeout: 3), "bubble should appear after tapping pet")
    XCTAssertTrue(focusLabel.exists, "专注 action should be visible")
    XCTAssertTrue(slackLabel.exists, "摸鱼 action should be visible")
    XCTAssertTrue(relaxLabel.exists, "放松 action should be visible")

    // Click the 专注 action in the bubble, then verify the bubble dismisses
    // (startFocus() hides the quick actions).
    let focusCenter = focusLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    focusCenter.click()
    let bubbleGone = bubble.waitForNonExistence(timeout: 2)
    if !bubbleGone {
      print("DEBUG UI TREE AFTER FOCUS CLICK:\n\(app.debugDescription)")
    }
    XCTAssertTrue(bubbleGone, "bubble should dismiss after tapping 专注")

    // Re-open the bubble, then click 放松 — the pet should enter the
    // sleeping state (moon.zzz effect appears) and the bubble dismisses.
    avatar.tap()
    XCTAssertTrue(
      relaxLabel.waitForExistence(timeout: 2), "bubble should reappear after second tap")
    let relaxCenter = relaxLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    relaxCenter.click()
    XCTAssertTrue(
      bubble.waitForNonExistence(timeout: 2),
      "bubble should dismiss after tapping 放松")
  }

  @MainActor
  func testPetCanBeDraggedToUpperScreen() {
    let app = XCUIApplication()
    app.launchArguments = ["--reset-window-position", "--demo-state", "working"]
    app.launch()

    let avatar = app.descendants(matching: .any)["pet.avatar"]
    XCTAssertTrue(avatar.waitForExistence(timeout: 5), "pet avatar should appear")
    // borderless NSPanel 不在 XCUITest 的 windows 查询里，用 avatar 的
    // 屏幕坐标判断窗口是否被拖向屏幕上方（macOS 屏幕坐标 y 向上，
    // 窗口上移时 minY 增大）。
    let before = avatar.frame

    // 把宠物向上拖动约 300pt（更靠近屏幕顶部）。
    let start = avatar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = start.withOffset(CGVector(dx: 0, dy: -300))
    start.press(forDuration: 0.1, thenDragTo: end)

    let after = avatar.frame
    XCTAssertLessThan(
      after.minY, before.minY - 100,
      "dragging the pet upward should move it toward the upper screen")
  }
}
