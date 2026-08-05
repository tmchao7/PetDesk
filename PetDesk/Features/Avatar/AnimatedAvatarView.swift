import AppKit
import SwiftUI

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

/// 帧动画头像视图：
/// - 多帧自定义行（multiFrameCount > 1）：按导入帧循环播放，速度随 CPU 变化
///   （RunCat 风格：0% CPU ≈ 5 FPS，100% CPU ≈ 100 FPS），由 TimelineView
///   的 display-link 驱动（窗口遮挡时自动暂停）。
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
  /// 窗口隐藏/遮挡时为 true：暂停动画（不实例化 TimelineView，显示静态帧）。
  var isPaused: Bool = false

  /// 预切片帧缓存：帧在精灵图/行/帧数变化时一次性准备，
  /// 播放期间复用，不在 body 中 crop 或包装 NSImage。
  /// 引用对象的属性不会在 body 求值期间触发 SwiftUI 状态发布。
  @State private var frameStore = AnimationFrameStore()
  /// 动画计时起点（视图生命周期内稳定；帧索引由 elapsed/interval 纯函数推导）。
  @State private var animationStart = Date()

  private var row: AnimationRow { animState.row }

  /// 当前行预切片帧（nil 时用单帧静态路径）。
  private var preparedFrames: AnimationFrameStore.PreparedAnimationFrames? {
    guard let spritesheet else { return nil }
    return frameStore.preload(sheet: spritesheet, row: row, frameCount: multiFrameCount)
  }

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
        if multiFrameCount > 1, !isPaused {
          // 多帧动画：TimelineView 按 CPU 驱动间隔（5~30 FPS）周期重算 body，
          // 帧索引 = elapsed / interval（纯函数，无 Timer/runloop 依赖）。
          // 窗口隐藏/遮挡时 isPaused 为 true：不实例化 TimelineView，
          // 显示静态帧，零动画工作。
          let interval = Self.computeInterval(
            cpu: cpuProvider(),
            speedMultiplier: speedMultiplier
          )
          TimelineView(.periodic(from: .now, by: interval)) { context in
            spriteView(frameIndex: frameIndex(at: context.date))
          }
        } else {
          spriteView(frameIndex: staticFrameIndex)
        }
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
    .onDisappear {
      frameStore.clear()
    }
    .accessibilityLabel("Pet avatar")
    .accessibilityIdentifier("pet.avatar")
  }

  /// 精灵图路径：保持 192×208 比例、无边框无卡片，背景完全透明，
  /// 只给角色本体加一点投影，在浅色桌面上仍可辨认。
  /// 帧图来自预切片缓存，不在 body 中 crop 或包装 NSImage。
  private func spriteView(frameIndex: Int) -> some View {
    let frames = preparedFrames
    let safeIndex = frames.map { frameIndex % $0.count } ?? 0
    let image = frames?.nsImages[safeIndex] ?? imagePlaceholder
    return Image(nsImage: image)
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .frame(width: spriteSize.width, height: spriteSize.height)
      .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
  }

  /// 无精灵帧时的兜底（不触发 crop）。
  private var imagePlaceholder: NSImage {
    let ctx = CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cg = ctx.makeImage()!
    return NSImage(
      cgImage: cg,
      size: NSSize(width: SpriteSheetSpec.frameWidth, height: SpriteSheetSpec.frameHeight)
    )
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

  /// 多帧动画当前帧索引：从动画起点起按 CPU 驱动间隔推进（纯函数）。
  /// - Parameter date: TimelineView 提供的当前时间。
  func frameIndex(at date: Date) -> Int {
    let interval = Self.computeInterval(
      cpu: cpuProvider(),
      speedMultiplier: speedMultiplier
    )
    let elapsed = max(0, date.timeIntervalSince(animationStart))
    return Self.frameIndex(elapsed: elapsed, interval: interval, frameCount: multiFrameCount)
  }

  /// 用户可调动画速度倍率（0.25× ~ 4.0×），由 AppEnvironment 注入。
  var speedMultiplier: Double = 1.0

  /// 帧索引推导（纯函数，可测试）：elapsed 每过一个 interval 推进一帧，
  /// 超过 frameCount 循环回绕。
  static func frameIndex(elapsed: TimeInterval, interval: TimeInterval, frameCount: Int) -> Int {
    let frames = max(1, frameCount)
    guard interval > 0 else { return 0 }
    return Int(elapsed / interval) % frames
  }

  /// 静态模式下每个状态行显示的基准帧（避开眨眼/位移/旋转帧）。
  private var staticFrameIndex: Int {
    switch row {
    case .happy, .surprised: 1
    default: 0
    }
  }

  /// RunCat 风格 CPU→帧间隔映射，v1 优化后夹紧到 5~30 FPS：
  /// 0% CPU ≈ 200ms/帧（5 FPS），100% CPU ≈ 33.3ms/帧（30 FPS），非线性加速。
  /// 上限 30 FPS 防止 CPU 升高形成动画正反馈；用户倍率夹紧后仍不越界。
  /// - Parameter speedMultiplier: 用户可调倍率（>0）；越大动画越快。
  static func computeInterval(cpu: Double, speedMultiplier: Double = 1.0) -> TimeInterval {
    let cpuPercent = max(0, min(1, cpu)) * 100
    let base = max(1.0 / 30.0, min(0.20, 0.20 / max(1.0, min(20.0, cpuPercent / 5.0))))
    let multiplier = max(0.1, speedMultiplier)
    return max(1.0 / 30.0, min(0.20, base / multiplier))
  }
}
