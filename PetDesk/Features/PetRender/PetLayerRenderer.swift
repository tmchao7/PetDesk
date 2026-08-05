import AppKit
import CoreGraphics
import QuartzCore

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// CALayer 离散帧动画的动画内容配置（可测试、可比较）：
/// 只描述“播放什么”（帧数 + 基准时长），不含暂停/速度状态——
/// 暂停与速度是播放器状态，不能进入内容相等判定（否则每次暂停/恢复
/// 或 CPU 速度变化都会重建动画）。
struct PetLayerAnimationConfiguration: Equatable {
  let frameCount: Int
  /// 动画内容基准帧间隔（秒）：keyframe 动画时长 = frameCount × baseFrameDuration。
  let baseFrameDuration: TimeInterval

  init(frameCount: Int, baseFrameDuration: TimeInterval) {
    self.frameCount = max(0, frameCount)
    // 基准时长夹紧到 1/30s ~ 0.20s。
    self.baseFrameDuration = min(0.20, max(1.0 / 30.0, baseFrameDuration))
  }

  var totalDuration: TimeInterval {
    baseFrameDuration * Double(max(0, frameCount))
  }
}

/// AppKit 视图 + CALayer 离散帧动画播放器（RunCatNeo 风格）：
/// - CAKeyframeAnimation 内容固定（帧列表 + 基准时长），播放速度通过
///   layer.speed 独立调整——CPU 变化不重建动画、不重置到第一帧。
/// - 暂停/恢复按 Apple QA1673 标准公式，作为状态转换只执行一次（幂等）。
@MainActor
final class PetLayerRenderer: NSView {
  private let animationLayer = CALayer()
  private var currentImages: [CGImage] = []
  private var currentConfig: PetLayerAnimationConfiguration?
  private var isPaused = false
  /// 当前已生效的播放速度（幂等判定：相同速度不重写时间状态）。
  private var currentSpeed: Double = 1.0
  /// 暂停期间收到的目标速度（恢复后应用）。
  private var pendingSpeed: Double = 1.0

  /// 测试接口：动画对象重建次数（内容变化才递增）。
  private(set) var animationRebuildCount = 0
  /// 测试接口：当前是否处于暂停状态。
  private(set) var isAnimationPaused = false
  /// 当前播放的帧列表（测试可读）。
  var displayedImages: [CGImage] { currentImages }
  /// 测试接口：当前生效的播放速度倍率。
  private(set) var effectiveSpeed: Double = 1.0
  /// 测试接口：当前动画 local time（时间连续性断言用）。
  var currentLayerLocalTime: TimeInterval {
    animationLayer.convertTime(CACurrentMediaTime(), from: nil)
  }

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

  /// 更新播放内容与状态。
  /// - Parameters:
  ///   - images: 预切片帧（内容变化时重建动画）。
  ///   - config: 动画内容（帧数 + 基准时长）。
  ///   - isPaused: 暂停状态（转换幂等；不触发动画重建）。
  ///   - speed: 播放速度倍率（1.0 = 基准帧率；通过 layer.speed 调整，不重建动画）。
  func update(
    images: [CGImage],
    config: PetLayerAnimationConfiguration,
    isPaused: Bool,
    speed: Double = 1.0
  ) {
    let imagesChanged =
      images.count != currentImages.count
      || !images.elementsEqual(currentImages, by: { $0 === $1 })
    let contentChanged = currentConfig != config

    // 内容变化：移除旧动画、安装新动画（暂停期间保持暂停，显示新首帧）。
    if imagesChanged || contentChanged {
      currentImages = images
      currentConfig = config
      if images.isEmpty {
        removeAnimation()
        return
      }
      installAnimation(images: images, config: config)
      // 内容变化后明确设置初始帧（暂停时不播放，contents 显示首帧）。
      animationLayer.contents = images.first
    }

    // 暂停/恢复是状态转换，不是内容变化：QA1673 公式，只执行一次。
    if isPaused {
      // 暂停期间记录目标速度，恢复后应用；不得让 speed 参数触发播放。
      pendingSpeed = max(0.1, speed)
      pauseLayerIfNeeded()
    } else {
      resumeLayerIfNeeded()
      // 速度变化通过时间保持转换应用（RunCatNeo 风格），
      // 直接赋 layer.speed 会改变时间映射导致跳帧。
      applySpeedTransition(to: max(0.1, speed))
    }
  }

  /// 移除动画并清空内容（sheet 移除/零帧时调用）。
  func clearContents() {
    removeAnimation()
    currentImages = []
    currentConfig = nil
    isPaused = false
    isAnimationPaused = false
  }

  // MARK: - Private

  /// 安装（或重建）离散帧动画；暂停状态由调用方在安装后保持。
  private func installAnimation(images: [CGImage], config: PetLayerAnimationConfiguration) {
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = images
    animation.keyTimes = Self.keyTimes(for: images.count)
    animation.duration = config.totalDuration
    animation.repeatCount = .greatestFiniteMagnitude
    animation.calculationMode = .discrete
    animation.isRemovedOnCompletion = false
    animationLayer.removeAnimation(forKey: "petFrameAnimation")
    animationLayer.add(animation, forKey: "petFrameAnimation")
    animationRebuildCount += 1
    // 内容已重置：清掉旧暂停偏移，从第 0 帧以基准速度起播。
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
    animationLayer.speed = 1
    currentSpeed = 1.0
    pendingSpeed = 1.0
    effectiveSpeed = 1.0
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

  /// QA1673 暂停：speed = 0，timeOffset = 当前层时间。
  /// 幂等：已暂停时不再重写 timeOffset；无动画时保持未暂停（无可暂停内容）。
  private func pauseLayerIfNeeded() {
    guard !isPaused else { return }
    guard animationLayer.animation(forKey: "petFrameAnimation") != nil else { return }
    isPaused = true
    isAnimationPaused = true
    let pausedTime = animationLayer.convertTime(CACurrentMediaTime(), from: nil)
    animationLayer.speed = 0
    animationLayer.timeOffset = pausedTime
  }

  /// QA1673 恢复：pausedTime = timeOffset；speed = 1；timeOffset = 0；
  /// beginTime = 0；beginTime = 当前层时间 - pausedTime。
  /// 恢复后应用暂停期间记录的目标速度（时间保持转换，不跳帧）。
  /// 幂等：未暂停时直接返回。
  private func resumeLayerIfNeeded() {
    guard isPaused else { return }
    let pausedTime = animationLayer.timeOffset
    animationLayer.speed = 1
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
    animationLayer.beginTime =
      animationLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    isPaused = false
    isAnimationPaused = false
    // 恢复后应用目标速度：从 speed=1 经时间保持转换到目标，位置连续。
    let target = max(0.1, pendingSpeed)
    applySpeedTransition(to: target)
    currentSpeed = target
    effectiveSpeed = target
  }

  /// 时间保持的速度切换：捕获当前动画 local time，围绕过渡重设
  /// timeOffset/beginTime，再应用目标 speed——避免直接改 layer.speed
  /// 导致时间映射缩放造成跳帧。相同目标速度幂等（不重写时间状态）。
  private func applySpeedTransition(to targetSpeed: Double) {
    let clamped = max(0.1, targetSpeed)
    guard clamped != currentSpeed else { return }
    guard animationLayer.animation(forKey: "petFrameAnimation") != nil else {
      animationLayer.speed = Float(clamped)
      currentSpeed = clamped
      return
    }
    let now = CACurrentMediaTime()
    let currentLocalTime = animationLayer.convertTime(now, from: nil)
    animationLayer.timeOffset = currentLocalTime
    animationLayer.beginTime = now
    animationLayer.speed = Float(clamped)
    currentSpeed = clamped
    effectiveSpeed = clamped
  }

  private func removeAnimation() {
    animationLayer.removeAnimation(forKey: "petFrameAnimation")
    animationLayer.contents = nil
    animationLayer.speed = 1
    animationLayer.timeOffset = 0
    animationLayer.beginTime = 0
    isPaused = false
    isAnimationPaused = false
    currentSpeed = 1.0
    pendingSpeed = 1.0
    effectiveSpeed = 1.0
  }
}
