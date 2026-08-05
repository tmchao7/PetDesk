import AppKit
import CoreGraphics
import XCTest

@testable import PetDesk

final class PetLayerRendererTests: XCTestCase {
  /// 空帧列表必须安全（不创建动画）。
  @MainActor
  func testEmptyFrameListIsSafe() {
    let config = PetLayerAnimationConfiguration(frameCount: 0, baseFrameDuration: 0.1)
    XCTAssertEqual(config.frameCount, 0)
  }

  /// 基准时长必须夹紧到 1/30s ~ 0.20s。
  @MainActor
  func testBaseFrameDurationIsClamped() {
    let tooFast = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 0.001)
    XCTAssertEqual(tooFast.baseFrameDuration, 1.0 / 30.0, accuracy: 0.001)
    let tooSlow = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 5.0)
    XCTAssertEqual(tooSlow.baseFrameDuration, 0.20, accuracy: 0.001)
    let normal = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 0.05)
    XCTAssertEqual(normal.baseFrameDuration, 0.05, accuracy: 0.001)
  }

  /// 内容配置只描述播放内容：暂停状态不在配置里（避免暂停触发重建）。
  @MainActor
  func testConfigExcludesPauseState() {
    let a = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 0.1)
    let b = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 0.1)
    XCTAssertEqual(a, b, "pause must not be part of the content config")
  }

  /// 动画总时长 = 基准时长 × 帧数。
  @MainActor
  func testTotalDurationIsBaseFrameDurationTimesFrameCount() {
    let config = PetLayerAnimationConfiguration(frameCount: 8, baseFrameDuration: 0.1)
    XCTAssertEqual(config.totalDuration, 0.8, accuracy: 0.001)
  }

  /// CAKeyframeAnimation requires keyTimes and values to have identical counts.
  @MainActor
  func testKeyTimesMatchFrameCount() {
    let keyTimes = PetLayerRenderer.keyTimes(for: 8)
    XCTAssertEqual(keyTimes.count, 8)
    XCTAssertEqual(keyTimes.first?.doubleValue ?? -1, 0, accuracy: 0.001)
    XCTAssertEqual(keyTimes.last?.doubleValue ?? -1, 0.875, accuracy: 0.001)
  }

  // MARK: - Renderer 状态转换

  /// pause -> resume 不重建动画，且恢复后保持播放（时间位置不重置）。
  @MainActor
  func testPauseResumeDoesNotRebuildAnimation() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    renderer.update(
      images: images,
      config: PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1),
      isPaused: false,
      speed: 1.0
    )
    let rebuildsAfterInstall = renderer.animationRebuildCount
    XCTAssertEqual(rebuildsAfterInstall, 1)

    renderer.update(
      images: images,
      config: PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1),
      isPaused: true,
      speed: 1.0
    )
    XCTAssertTrue(renderer.isAnimationPaused)

    renderer.update(
      images: images,
      config: PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1),
      isPaused: false,
      speed: 1.0
    )
    XCTAssertFalse(renderer.isAnimationPaused)
    XCTAssertEqual(
      renderer.animationRebuildCount, rebuildsAfterInstall,
      "pause/resume must not rebuild the CAKeyframeAnimation")
  }

  /// 重复 pause 幂等：不重复写入 timeOffset（重建计数不变，状态保持暂停）。
  @MainActor
  func testRepeatedPauseIsIdempotent() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: true, speed: 1.0)
    let rebuildsAfterFirstPause = renderer.animationRebuildCount

    // 重复收到 paused=true（例如 window 每帧都发布 pause）不重建、不跳帧。
    renderer.update(images: images, config: config, isPaused: true, speed: 1.0)
    XCTAssertTrue(renderer.isAnimationPaused)
    XCTAssertEqual(renderer.animationRebuildCount, rebuildsAfterFirstPause)
  }

  /// 暂停期间替换 images：移除旧动画、安装新动画、保持暂停、显示新首帧。
  @MainActor
  func testReplacingImagesWhilePausedStaysPaused() {
    let renderer = PetLayerRenderer()
    let first = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: first, config: config, isPaused: true, speed: 1.0)
    XCTAssertTrue(renderer.isAnimationPaused)

    let second = makeFrames(4, seed: 99)
    renderer.update(images: second, config: config, isPaused: true, speed: 1.0)
    XCTAssertTrue(
      renderer.isAnimationPaused,
      "replacing images while paused must stay paused")
    XCTAssertEqual(
      renderer.animationRebuildCount, 2,
      "content change should rebuild once")
    XCTAssertTrue(
      renderer.displayedImages[0] === second[0],
      "paused content replacement should show the new first frame")
  }

  /// 暂停期间替换内容后，CALayer 的实际 local time 也必须保持冻结，
  /// 不能只保留 isAnimationPaused 标志而让新动画以基准速度播放。
  @MainActor
  func testReplacingImagesWhilePausedFreezesNewAnimation() {
    let renderer = PetLayerRenderer()
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: makeFrames(4), config: config, isPaused: true, speed: 1.0)

    renderer.update(
      images: makeFrames(4, seed: 99), config: config, isPaused: true, speed: 1.0)
    let before = renderer.currentLayerLocalTime
    Thread.sleep(forTimeInterval: 0.03)
    let after = renderer.currentLayerLocalTime

    XCTAssertTrue(renderer.isAnimationPaused)
    XCTAssertEqual(
      after, before, accuracy: 0.01,
      "replacing content while paused must keep the new animation frozen")
  }

  /// CPU-only 速度变化不重建动画。
  @MainActor
  func testSpeedChangeDoesNotRebuildAnimation() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 0.5)
    let rebuildsAfterInstall = renderer.animationRebuildCount

    renderer.update(images: images, config: config, isPaused: false, speed: 3.0)
    XCTAssertEqual(
      renderer.animationRebuildCount, rebuildsAfterInstall,
      "CPU-driven speed change must not rebuild the animation")
  }

  /// 速度切换（0.5x -> 3.0x）保持动画 local time 连续：时间保持转换
  /// 不得因 speed 改变导致当前帧位置跳变。
  @MainActor
  func testSpeedChangePreservesLocalTimeContinuity() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 0.5)
    // 让动画真正走一小段时间（runloop 不驱动 layer，但 timeOffset/beginTime
    // 已建立，convertTime 反映媒体时间映射）。
    Thread.sleep(forTimeInterval: 0.05)

    let before = renderer.currentLayerLocalTime
    renderer.update(images: images, config: config, isPaused: false, speed: 3.0)
    let after = renderer.currentLayerLocalTime

    XCTAssertEqual(
      abs(after - before) < 0.1, true,
      "speed change must preserve local time (jump was \(after - before))")
    XCTAssertEqual(renderer.effectiveSpeed, 3.0, accuracy: 0.001)
  }

  /// pause -> speed change -> resume：resume 后应用目标速度，位置连续。
  @MainActor
  func testPauseSpeedChangeResumeAppliesTargetSpeed() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 1.0)

    renderer.update(images: images, config: config, isPaused: true, speed: 1.0)
    let pausedTime = renderer.currentLayerLocalTime
    // 暂停期间收到新速度：不得播放。
    renderer.update(images: images, config: config, isPaused: true, speed: 3.0)
    XCTAssertTrue(renderer.isAnimationPaused)
    XCTAssertEqual(
      renderer.currentLayerLocalTime, pausedTime, accuracy: 0.01,
      "paused layer must not advance while speed changes arrive")

    renderer.update(images: images, config: config, isPaused: false, speed: 3.0)
    XCTAssertFalse(renderer.isAnimationPaused)
    XCTAssertEqual(
      renderer.effectiveSpeed, 3.0, accuracy: 0.001,
      "resume must apply the target speed captured while paused")
  }

  /// 暂停/恢复且速度未变化时，QA1673 的 speed=1 归一化不能吞掉原目标速度。
  @MainActor
  func testResumeRestoresUnchangedNonDefaultLayerSpeed() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 3.0)
    XCTAssertEqual(renderer.currentLayerSpeed, 3.0, accuracy: 0.001)

    renderer.update(images: images, config: config, isPaused: true, speed: 3.0)
    renderer.update(images: images, config: config, isPaused: false, speed: 3.0)

    XCTAssertEqual(
      renderer.currentLayerSpeed, 3.0, accuracy: 0.001,
      "resume must restore the actual layer speed even when the target is unchanged")
  }

  /// 相同速度重复 update 不重写时间状态（local time 不受干扰）。
  @MainActor
  func testIdenticalSpeedDoesNotRewriteTime() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 2.0)
    Thread.sleep(forTimeInterval: 0.02)
    let before = renderer.currentLayerLocalTime
    let rebuilds = renderer.animationRebuildCount

    renderer.update(images: images, config: config, isPaused: false, speed: 2.0)
    XCTAssertEqual(renderer.animationRebuildCount, rebuilds)
    // 时间保持转换幂等：相同速度不重设 timeOffset/beginTime，
    // local time 只随媒体时间自然前进（不跳变）。
    let after = renderer.currentLayerLocalTime
    XCTAssertGreaterThan(after, before, "media time should still advance")
    XCTAssertLessThan(after - before, 1.0, "no jump from identical speed update")
  }

  /// 空 images -> pause -> 重新加载 images：状态完全重置后正常播放。
  @MainActor
  func testEmptyImagesThenPauseThenReload() {
    let renderer = PetLayerRenderer()
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: [], config: config, isPaused: false, speed: 2.0)
    XCTAssertFalse(renderer.isAnimationPaused)

    renderer.update(images: [], config: config, isPaused: true, speed: 2.0)
    XCTAssertFalse(renderer.isAnimationPaused, "no animation to pause")

    let images = makeFrames(4)
    renderer.update(images: images, config: config, isPaused: false, speed: 1.0)
    XCTAssertFalse(renderer.isAnimationPaused)
    XCTAssertEqual(renderer.effectiveSpeed, 1.0, accuracy: 0.001)
    XCTAssertEqual(renderer.displayedImages.count, 4)
  }

  /// clearContents 后重新加入 images 能正常播放。
  @MainActor
  func testClearThenReplay() {
    let renderer = PetLayerRenderer()
    let images = makeFrames(4)
    let config = PetLayerAnimationConfiguration(frameCount: 4, baseFrameDuration: 0.1)
    renderer.update(images: images, config: config, isPaused: false, speed: 1.0)
    renderer.clearContents()
    XCTAssertFalse(renderer.isAnimationPaused)
    XCTAssertEqual(renderer.displayedImages.count, 0)

    renderer.update(images: images, config: config, isPaused: false, speed: 1.0)
    XCTAssertEqual(renderer.animationRebuildCount, 2)
    XCTAssertEqual(renderer.displayedImages.count, 4)
  }

  // MARK: - Helpers

  @MainActor
  private func makeFrames(_ count: Int, seed: Int = 0) -> [CGImage] {
    (0..<count).map { i in
      let ctx = CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      ctx.setFillColor(
        CGColor(
          red: CGFloat(seed + i) / 255, green: 0.5, blue: 0.5, alpha: 1))
      ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
      return ctx.makeImage()!
    }
  }
}
