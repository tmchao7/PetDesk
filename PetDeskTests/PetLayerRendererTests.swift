import CoreGraphics
import XCTest

@testable import PetDesk

final class PetLayerRendererTests: XCTestCase {
  /// 空帧列表必须安全（不创建动画）。
  @MainActor
  func testEmptyFrameListIsSafe() {
    let config = PetLayerAnimationConfiguration(
      frameCount: 0,
      frameDuration: 0.1,
      isPaused: false
    )
    XCTAssertEqual(config.frameCount, 0)
    XCTAssertFalse(config.isPaused)
  }

  /// 帧时长必须夹紧到 1/30s ~ 0.20s。
  @MainActor
  func testFrameDurationIsClamped() {
    let tooFast = PetLayerAnimationConfiguration(
      frameCount: 8, frameDuration: 0.001, isPaused: false)
    XCTAssertEqual(tooFast.frameDuration, 1.0 / 30.0, accuracy: 0.001)
    let tooSlow = PetLayerAnimationConfiguration(frameCount: 8, frameDuration: 5.0, isPaused: false)
    XCTAssertEqual(tooSlow.frameDuration, 0.20, accuracy: 0.001)
    let normal = PetLayerAnimationConfiguration(frameCount: 8, frameDuration: 0.05, isPaused: false)
    XCTAssertEqual(normal.frameDuration, 0.05, accuracy: 0.001)
  }

  /// 暂停状态必须被表示，且不创建重复动画。
  @MainActor
  func testPauseStateRepresentedWithoutRepeatingAnimation() {
    let paused = PetLayerAnimationConfiguration(frameCount: 8, frameDuration: 0.1, isPaused: true)
    XCTAssertTrue(paused.isPaused)
    // 相同配置相等：幂等更新判定依赖 Equatable。
    let same = PetLayerAnimationConfiguration(frameCount: 8, frameDuration: 0.1, isPaused: true)
    XCTAssertEqual(paused, same)
    let different = PetLayerAnimationConfiguration(
      frameCount: 8, frameDuration: 0.1, isPaused: false)
    XCTAssertNotEqual(paused, different)
  }

  /// 动画总时长 = 帧时长 × 帧数。
  @MainActor
  func testTotalDurationIsFrameDurationTimesFrameCount() {
    let config = PetLayerAnimationConfiguration(frameCount: 8, frameDuration: 0.1, isPaused: false)
    XCTAssertEqual(config.totalDuration, 0.8, accuracy: 0.001)
  }
}
