import AppKit
import CoreGraphics
import QuartzCore

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// CALayer 离散帧动画的纯配置值（可测试、可比较）：
/// 相同配置的更新必须幂等——不重建动画。
struct PetLayerAnimationConfiguration: Equatable {
  let frameCount: Int
  let frameDuration: TimeInterval
  let isPaused: Bool

  init(frameCount: Int, frameDuration: TimeInterval, isPaused: Bool) {
    self.frameCount = max(0, frameCount)
    // 帧时长夹紧到 1/30s ~ 0.20s（30 FPS 上限、5 FPS 下限）。
    self.frameDuration = min(0.20, max(1.0 / 30.0, frameDuration))
    self.isPaused = isPaused
  }

  var totalDuration: TimeInterval {
    frameDuration * Double(max(0, frameCount))
  }
}

/// AppKit 视图 + CALayer 离散帧动画播放器。
/// 预切片好的 CGImage 帧通过 `update` 一次性注入；
/// CAKeyframeAnimation 只在该行帧/时长/暂停状态变化时重建。
@MainActor
final class PetLayerRenderer: NSView {
  private let animationLayer = CALayer()
  private var currentImages: [CGImage] = []
  private var currentConfig: PetLayerAnimationConfiguration?
  private var needsAnimationUpdate = false

  /// 当前播放的帧列表（测试可读）。
  var displayedImages: [CGImage] { currentImages }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    animationLayer.contentsGravity = .resizeAspect
    animationLayer.backgroundColor = CGColor.clear
    layer?.addSublayer(animationLayer)
    // XCUITest 依赖 pet.avatar 标识；NSViewRepresentable 的 SwiftUI
    // accessibility modifier 不会作用到 NSView，必须在 NSView 层设置。
    setAccessibilityElement(true)
    setAccessibilityIdentifier("pet.avatar")
    setAccessibilityLabel("Pet avatar")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    animationLayer.frame = bounds
  }

  /// 更新播放内容。幂等：帧列表、时长、暂停状态都未变时不重建动画。
  func update(images: [CGImage], config: PetLayerAnimationConfiguration) {
    let imagesChanged =
      images.count != currentImages.count
      || !images.elementsEqual(currentImages, by: { $0 === $1 })
    let configChanged = currentConfig != config

    currentImages = images
    currentConfig = config
    needsAnimationUpdate = imagesChanged || configChanged

    guard !images.isEmpty else {
      removeAnimation()
      return
    }

    animationLayer.contents = images.first
    if config.isPaused {
      pauseLayer()
    } else if needsAnimationUpdate {
      startAnimation(images: images, config: config)
    } else if animationLayer.speed == 0 {
      resumeLayer()
    }
  }

  /// 移除动画并清空内容（sheet 移除/零帧时调用）。
  func clearContents() {
    removeAnimation()
    currentImages = []
    currentConfig = nil
    animationLayer.contents = nil
  }

  // MARK: - Private

  private func startAnimation(images: [CGImage], config: PetLayerAnimationConfiguration) {
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = images
    animation.keyTimes = Self.keyTimes(for: images.count)
    animation.duration = config.totalDuration
    animation.repeatCount = .greatestFiniteMagnitude
    animation.calculationMode = .discrete
    animation.isRemovedOnCompletion = false
    animationLayer.removeAnimation(forKey: "petFrameAnimation")
    animationLayer.add(animation, forKey: "petFrameAnimation")
    animationLayer.speed = 1
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
  }

  /// Core Animation requires one key time per value. The final frame's
  /// interval ends at the repeat boundary, so no extra key time at 1.0 is
  /// needed for a repeating discrete animation.
  static func keyTimes(for frameCount: Int) -> [NSNumber] {
    guard frameCount > 0 else { return [] }
    return (0..<frameCount).map {
      NSNumber(value: Double($0) / Double(frameCount))
    }
  }

  private func pauseLayer() {
    guard animationLayer.animation(forKey: "petFrameAnimation") != nil else { return }
    let pausedTime = animationLayer.convertTime(CACurrentMediaTime(), from: nil)
    animationLayer.speed = 0
    animationLayer.timeOffset = pausedTime
  }

  private func resumeLayer() {
    let pausedTime = animationLayer.timeOffset
    animationLayer.speed = 1
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
    animationLayer.beginTime =
      animationLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
  }

  private func removeAnimation() {
    animationLayer.removeAnimation(forKey: "petFrameAnimation")
    animationLayer.contents = nil
    animationLayer.speed = 1
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
  }
}
