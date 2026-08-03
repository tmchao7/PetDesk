import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// 帧动画头像视图：
/// - 多帧自定义行（multiFrameCount > 1）：按导入帧循环播放，速度随 CPU 变化
///   （RunCat 风格：0% CPU ≈ 5 FPS，100% CPU ≈ 100 FPS）
/// - 其余：静态显示当前状态行基准帧
/// - 无精灵图时回退为静态头像 + 轻微呼吸浮动
struct AnimatedAvatarView: View {
  let image: NSImage?
  let spritesheet: CGImage?
  let animState: PetAnimState
  let displayMode: AvatarDisplayMode
  let avatarSize: CGFloat
  /// 当前行自定义帧数：0/1 = 静态；>1 = 逐帧动画。
  let multiFrameCount: Int
  /// 读取最新 CPU（0~1）：动画速度用；闭包读取不触发 SwiftUI 重算。
  let cpuProvider: () -> Double

  /// 帧缓存：裁剪是 O(1) 但 NSImage 包装/释放有分配流量，状态切换时复用。
  /// cachedFrameSheet 强引用精灵图，保证缓存命中比较时其地址不被复用。
  @State private var cachedFrameSheet: CGImage?
  @State private var cachedFrame: (sheetID: UInt, row: AnimationRow, index: Int, image: NSImage)?
  /// 多帧动画驱动器（仅 multiFrameCount > 1 时运行 Timer）。
  @StateObject private var animator = FrameAnimator(frameCount: 1, cpuProvider: { 0 })

  private var row: AnimationRow { animState.row }

  /// 精灵帧是 192×208 竖构图，按同比例放大显示，避免方形框 scaledToFill
  /// 把上下边缘裁掉（角色会显得小、头脚被切）。
  private var spriteSize: CGSize {
    CGSize(
      width: avatarSize,
      height: avatarSize * SpriteSheetSpec.frameHeight / SpriteSheetSpec.frameWidth
    )
  }

  var body: some View {
    Group {
      if let spritesheet {
        spriteView(spritesheet)
      } else if let image {
        card {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
        }
      } else {
        card { placeholder }
      }
    }
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
    .onAppear { configureAnimator() }
    .onChange(of: multiFrameCount) { _ in configureAnimator() }
    .onDisappear { animator.stop() }
  }

  /// 多帧行启动动画驱动器（100Hz Timer），其余行停止（零唤醒开销）。
  private func configureAnimator() {
    if multiFrameCount > 1 {
      animator.configure(frameCount: multiFrameCount, cpuProvider: cpuProvider)
      animator.start()
    } else {
      animator.stop()
    }
  }

  /// 精灵图路径：保持 192×208 比例、无边框无卡片，背景完全透明，
  /// 只给角色本体加一点投影，在浅色桌面上仍可辨认。
  private func spriteView(_ sheet: CGImage) -> some View {
    Image(nsImage: cachedFrameImage(from: sheet))
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .frame(width: spriteSize.width, height: spriteSize.height)
      .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
  }

  /// 无精灵图时的卡片样式（保持原有圆形/圆角外观）。
  private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .clipShape(
        displayMode == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20))
      )
      .overlay(
        (displayMode == .circle
          ? AnyShape(Circle())
          : AnyShape(RoundedRectangle(cornerRadius: 20))).stroke(.white, lineWidth: 5)
      )
      .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
  }

  private var placeholder: some View {
    ZStack {
      Circle().fill(Color(red: 0.96, green: 0.82, blue: 0.72))
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: 76, weight: .regular))
        .foregroundStyle(.white.opacity(0.92))
    }
  }

  /// 按当前状态行裁剪帧（多帧动画或静态基准帧），结果按
  /// (精灵图地址, 行, 帧索引) 缓存复用。精灵图规范与 CGImage.cropping
  /// 同为“y=0 在视觉顶部”，直接按行/列裁剪，不做 y 翻转。
  private func cachedFrameImage(from sheet: CGImage) -> NSImage {
    let sheetID = UInt(bitPattern: Unmanaged.passUnretained(sheet).toOpaque())
    let index = displayFrameIndex
    if let cached = cachedFrame, cached.sheetID == sheetID, cached.row == row,
      cached.index == index
    {
      return cached.image
    }
    // 多帧动画直接按列索引裁剪（帧数可能超过 row.frameCount 的 clamp 范围）；
    // 静态路径复用 frameRect 的行映射。
    let y = CGFloat(row.rawValue) * SpriteSheetSpec.frameHeight
    let cropRect = CGRect(
      x: CGFloat(index) * SpriteSheetSpec.frameWidth,
      y: y,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
    let cropped = sheet.cropping(to: cropRect) ?? sheet
    let image = NSImage(
      cgImage: cropped,
      size: NSSize(width: SpriteSheetSpec.frameWidth, height: SpriteSheetSpec.frameHeight)
    )
    // 先强引用精灵图再缓存，保证地址在命中比较期间不被复用。
    cachedFrameSheet = sheet
    cachedFrame = (sheetID, row, index, image)
    return image
  }

  /// 当前显示的帧索引：多帧行取动画推进的帧，其余行取静态基准帧。
  private var displayFrameIndex: Int {
    if multiFrameCount > 1 { return animator.frameIndex }
    return staticFrameIndex
  }

  /// 静态模式下每个状态行显示的基准帧（避开眨眼/位移/旋转帧）。
  private var staticFrameIndex: Int {
    switch row {
    case .happy, .surprised: 1
    default: 0
    }
  }
}

/// 多帧动画驱动器：100Hz Timer 累计时间，按 CPU 映射的帧间隔推进帧索引。
/// 仅在多帧行显示时运行（start/stop 控制），空闲时零唤醒开销。
@MainActor
final class FrameAnimator: ObservableObject {
  @Published private(set) var frameIndex = 0

  private var frameCount = 1
  private var cpuProvider: () -> Double = { 0 }
  private var timer: Timer?
  private var accumulated: TimeInterval = 0
  private var lastTick: TimeInterval = 0

  init(frameCount: Int, cpuProvider: @escaping () -> Double) {
    configure(frameCount: frameCount, cpuProvider: cpuProvider)
  }

  func configure(frameCount: Int, cpuProvider: @escaping () -> Double) {
    self.frameCount = max(1, frameCount)
    self.cpuProvider = cpuProvider
    frameIndex = 0
    accumulated = 0
  }

  func start() {
    guard timer == nil else { return }
    lastTick = CACurrentMediaTime()
    // scheduledTimer 的回调在 main runloop 执行，直接 assumeIsolated
    // 直调（避免每 tick 创建 Task 的 100Hz 开销）。
    timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    let now = CACurrentMediaTime()
    let dt = now - lastTick
    lastTick = now
    accumulated += dt
    let interval = Self.computeInterval(cpu: cpuProvider())
    if accumulated >= interval {
      accumulated = 0
      frameIndex = (frameIndex + 1) % frameCount
    }
  }

  /// RunCat 风格 CPU→帧间隔映射：0% CPU ≈ 200ms/帧（5 FPS），
  /// 100% CPU ≈ 10ms/帧（100 FPS），非线性加速。
  static func computeInterval(cpu: Double) -> TimeInterval {
    let cpuPercent = max(0, min(1, cpu)) * 100
    return max(0.01, min(0.20, 0.20 / max(1.0, min(20.0, cpuPercent / 5.0))))
  }
}
