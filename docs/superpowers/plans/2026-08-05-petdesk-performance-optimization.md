# PetDesk Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 PetDesk 多帧桌宠动画从高频 SwiftUI 重算和逐帧图像裁切，优化为有界帧率、可显式暂停、预切片缓存并最终由原生 `CALayer` 驱动，同时降低头像预览的常驻内存。

**Architecture:** 保留 `PetStateMachine` 作为唯一行为决策源，渲染层只接收已经决定的姿势、帧和暂停状态。短期先限制 `TimelineView` 为 5--30 FPS 并接通遮挡暂停；稳定后由 `PetLayerRenderer` 使用预加载 `CGImage` 的 `CAKeyframeAnimation` 替换 SwiftUI 时间线。CPU 采样仍由现有适配器负责，每秒只更新一次动画速度，不把 CPU 读数做成 SwiftUI 高频发布。

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, AppKit, Core Animation (`CALayer`/`CAKeyframeAnimation`), XCTest, XCUITest, `xcrun xctrace`, `scripts/measure-petdesk.sh`.

---

## Scope and Guardrails

- 只优化渲染和头像预览内存，不改变 `PetStateMachine` 的状态阈值、热状态语义、通知隐私边界或用户可见的状态优先级。
- 不引入 Lottie、WebView、Spine 或其他运行时依赖；所有动画能力使用 AppKit/Core Animation。
- 不读取精确温度、功耗、消息正文、文件名或头像路径；性能日志只记录场景、耗时、帧数和脱敏的资源计数。
- 不直接编辑生成的 `PetDesk.xcodeproj`；新增 Swift 文件由 `project.yml` 的 `PetDesk` source glob 自动纳入。
- 每个行为改动先写失败测试，确认失败后再实现；每个阶段单独使用 Conventional Commit。
- `picture.png` 是现有未跟踪文件，不能加入任何提交。

## Baseline and Acceptance Targets

在同一台 Apple Silicon Mac、同一份头像和同一套窗口位置上，分别记录静态头像、单帧姿势、8 帧姿势三种场景。Release 构建作为正式比较基线，Debug 数据只能作为诊断参考。

| 指标 | 当前已知事实 | v1 优化验收 |
| --- | --- | --- |
| 空闲静态头像 CPU | 现有测量约 9%（Debug，60 秒独立采样） | Release 平均低于 1%，或相对基线下降 50% 以上 |
| 8 帧姿势 CPU | 尚未有可重复 Release 基线 | 10 分钟平均低于 2%，不得随 CPU 升高形成正反馈 |
| RSS | 现有测量约 131.7 MB，未证明泄漏 | 10 分钟无持续增长；相对基线下降，目标接近 100 MB |
| 动画帧率 | 最高请求 100 FPS | 上限 30 FPS，下限 5 FPS；遮挡/隐藏时 0 FPS |
| 状态与专注行为 | 93 个单元测试、7 个 UI 测试已通过 | `make test`、`make lint`、`make verify` 全部通过 |

若硬件或 Xcode 版本无法达到绝对 CPU/RSS 数值，必须报告同机同场景的前后百分比和采样命令，不得把未运行的 Instruments 检查写成通过。

## File Map

| 文件 | 责任 |
| --- | --- |
| `PetDesk/Features/Avatar/AnimatedAvatarView.swift` | 短期时间线策略；最终只保留静态/回退渲染 |
| `PetDesk/Features/Avatar/AnimationFrameStore.swift` | 按精灵图、姿势行、帧数预切片并复用成对的 `CGImage`/`NSImage` |
| `PetDesk/Features/PetRender/PetLayerRenderer.swift` | AppKit `NSView` 与 `CALayer` 离散帧动画适配器 |
| `PetDesk/Features/PetRender/PetLayerRendererRepresentable.swift` | SwiftUI 到 AppKit 渲染器的最小桥接 |
| `PetDesk/Features/PetRender/PetView.swift` | 将 `isPetAnimationPaused`、帧数据和速度传给渲染器，不自行选择状态 |
| `PetDesk/App/AppEnvironment.swift` | 头像导入/恢复时只保留轻量预览；保持 CPU 读数非 `@Published` |
| `PetDesk/Features/Settings/SettingsView.swift` | 适配单预览缩略图数据结构 |
| `PetDeskTests/AnimationFrameStoreTests.swift` | 帧切片、复用、清理和边界测试 |
| `PetDeskTests/AppEnvironmentTests.swift` | 暂停传播、预览内存策略和现有动画策略回归 |
| `PetDeskTests/PetLayerRendererTests.swift` | 可测试的 Core Animation 配置策略 |
| `scripts/measure-petdesk.sh` | 重复测量 CPU/RSS；只增加场景说明或输出字段 |
| `docs/architecture/overview.md` | 渲染边界和性能约束 |
| `docs/debugging/runbook.md` | 动画暂停、Core Animation 和采样排障 |
| `docs/testing/test-plan.md` | 性能场景与验收记录方式 |
| `docs/agent-handoff/sessions/`、`CURRENT.md` | 每阶段不可变交接和下一步 |

### Task 1: Establish Reproducible Release Baselines

**Files:**
- Modify: `scripts/measure-petdesk.sh` only if needed to print build configuration and scenario labels.
- Create: `docs/performance/petdesk-baseline-2026-08.md`.
- Test: no production test; command-level measurement.

- [ ] **Step 1: Build the unsigned Release app and record the exact artifact path.**

Run:

```bash
make generate
xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Release -derivedDataPath /tmp/PetDeskDerived build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`; record the `PetDesk.app` path and commit hash in the baseline document.

- [ ] **Step 2: Measure static and one-frame scenarios.**

Run:

```bash
scripts/measure-petdesk.sh "/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app" 600 15
```

Run once with the default avatar and once after importing a single-frame pose. Record `samples`, `avg_cpu_pct`, `avg_rss_mb`, and `peak_rss_mb`.

- [ ] **Step 3: Measure the eight-frame scenario and capture a profile.**

Import an eight-frame row through the existing Settings flow, leave the pet visible and unobstructed, then run the same script for 600 seconds. Capture a Time Profiler trace with:

```bash
xcrun xctrace record --template 'Time Profiler' --launch "/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app" --time-limit 60s --output /tmp/petdesk-baseline.trace
```

If Allocations or Energy Log cannot attach under the installed Xcode, record that exact failure in the baseline document and continue with `ps`, Time Profiler, and RSS observations.

- [ ] **Step 4: Commit only the baseline artifact.**

```bash
git add docs/performance/petdesk-baseline-2026-08.md scripts/measure-petdesk.sh
git diff --cached --check
git commit -m "docs(performance): record release animation baseline"
```

### Task 2: Cap Timeline Work and Wire Explicit Pause

**Files:**
- Modify: `PetDesk/Features/Avatar/AnimatedAvatarView.swift:46-177`.
- Modify: `PetDesk/Features/PetRender/PetView.swift:43-61`.
- Test: `PetDeskTests/AppEnvironmentTests.swift` and the pure timing assertions already covering `frameIndex`/`computeInterval`.

- [ ] **Step 1: Add failing timing and pause assertions.**

Add assertions equivalent to:

```swift
func testAnimationIntervalIsBoundedToFiveThroughThirtyFPS() {
  XCTAssertEqual(AnimatedAvatarView.computeInterval(cpu: 0), 0.20, accuracy: 0.001)
  XCTAssertEqual(AnimatedAvatarView.computeInterval(cpu: 1), 1.0 / 30.0, accuracy: 0.001)
}

func testAnimationPauseFlagStartsPausedAndTracksWindowVisibility() {
  let environment = makeEnvironment()
  XCTAssertTrue(environment.isPetAnimationPaused)
  environment.updatePetAnimationPaused(false)
  XCTAssertFalse(environment.isPetAnimationPaused)
  environment.updatePetAnimationPaused(true)
  XCTAssertTrue(environment.isPetAnimationPaused)
}
```

Run the focused test before implementation and confirm the 100 FPS expectation fails after changing the intended contract.

- [ ] **Step 2: Pass the pause value through `PetView`.**

Add an `isPaused: Bool` input to `AnimatedAvatarView` and pass `environment.isPetAnimationPaused`. The animated branch must render one stable frame while paused and must not instantiate `TimelineView` in that branch:

```swift
if multiFrameCount > 1, !isPaused {
  TimelineView(.periodic(from: .now, by: animationInterval)) { context in
    spriteView(spritesheet, frameIndex: frameIndex(at: context.date))
  }
} else {
  spriteView(spritesheet, frameIndex: staticFrameIndex)
}
```

- [ ] **Step 3: Bound the interval and avoid CPU-positive feedback.**

Keep the existing monotonic CPU mapping, but clamp it to `0.20...1.0/30.0` seconds. Keep `speedMultiplier` as a user preference and clamp its result to the same range. CPU values are sampled once per second; do not add a display-link CPU sampler.

- [ ] **Step 4: Run focused tests and the full verification suite.**

```bash
xcodebuild test -project PetDesk.xcodeproj -scheme PetDesk -only-testing:PetDeskTests/AppEnvironmentTests
make test
make lint
make verify
```

Expected: all commands pass; the app no longer requests a 10ms timeline interval, and hiding/occluding the window sets the explicit pause flag.

- [ ] **Step 5: Commit the bounded fallback.**

```bash
git add PetDesk/Features/Avatar/AnimatedAvatarView.swift PetDesk/Features/PetRender/PetView.swift PetDeskTests/AppEnvironmentTests.swift
git diff --cached --check
git commit -m "perf(avatar): cap timeline animation and honor pause state"
```

### Task 3: Pre-slice and Reuse Animation Frames

**Files:**
- Create: `PetDesk/Features/Avatar/AnimationFrameStore.swift`.
- Modify: `PetDesk/Features/Avatar/AnimatedAvatarView.swift` to consume the store instead of cropping in `body`.
- Create: `PetDeskTests/AnimationFrameStoreTests.swift`.

- [ ] **Step 1: Write failing store tests.**

Cover the exact contracts below:

```swift
func testPreloadCreatesOnlyRequestedFrames() {
  let store = AnimationFrameStore()
  let sheet = makeTestSpriteSheet()
  let frames = store.preload(sheet: sheet, row: .working, frameCount: 3)
  XCTAssertEqual(frames.count, 3)
}

func testRepeatedPreloadReusesPreparedImagesUntilSheetChanges() {
  let store = AnimationFrameStore()
  let sheet = makeTestSpriteSheet()
  let first = store.preload(sheet: sheet, row: .working, frameCount: 3)
  let second = store.preload(sheet: sheet, row: .working, frameCount: 3)
  XCTAssertTrue(first.nsImages[0] === second.nsImages[0])
}

func testInvalidFrameCountProducesOneSafeFallbackFrame() {
  let store = AnimationFrameStore()
  XCTAssertEqual(store.preload(sheet: makeTestSpriteSheet(), row: .working, frameCount: 0).count, 1)
}
```

Run `xcodebuild test -only-testing:PetDeskTests/AnimationFrameStoreTests` and confirm failure because the store does not exist.

- [ ] **Step 2: Implement the store with one ownership boundary.**

The store must expose a single operation such as:

```swift
@MainActor
final class AnimationFrameStore {
  struct PreparedAnimationFrames {
    let cgImages: [CGImage]
    let nsImages: [NSImage]
    var count: Int { cgImages.count }
  }

  func preload(sheet: CGImage, row: AnimationRow, frameCount: Int) -> PreparedAnimationFrames
  func clear()
}
```

Use the existing `SpriteSheetSpec` cell rectangle. Cache all requested frames for the current sheet/row, retain the source `CGImage` while the cache is alive, clamp the frame count to the available columns, and fall back to the row's first cell when cropping fails. Never crop or construct `NSImage` from inside `AnimatedAvatarView.body`.

- [ ] **Step 3: Replace the one-frame `FrameCache`.**

On sheet, row, or frame-count changes, call `preload`; SwiftUI selects `prepared.nsImages[index % prepared.count]`, while the AppKit renderer receives the matching `prepared.cgImages`. Keep `frameIndex(elapsed:interval:frameCount:)` pure and unchanged except for the new interval bound. Clear the store when the sprite sheet is replaced or the view disappears.

- [ ] **Step 4: Run tests and inspect allocations.**

```bash
make test
xcrun xctrace record --template 'Time Profiler' --launch "/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app" --time-limit 60s --output /tmp/petdesk-preloaded.trace
```

Expected: frame changes no longer call `CGImage.cropping` or allocate an `NSImage`; the trace shows preparation at pose/sheet change rather than continuously during playback.

- [ ] **Step 5: Commit the frame store.**

```bash
git add PetDesk/Features/Avatar/AnimationFrameStore.swift PetDesk/Features/Avatar/AnimatedAvatarView.swift PetDeskTests/AnimationFrameStoreTests.swift
git diff --cached --check
git commit -m "perf(avatar): preload reusable animation frames"
```

### Task 4: Move Playback to a Native CALayer Renderer

**Files:**
- Create: `PetDesk/Features/PetRender/PetLayerRenderer.swift`.
- Create: `PetDesk/Features/PetRender/PetLayerRendererRepresentable.swift`.
- Modify: `PetDesk/Features/PetRender/PetView.swift` to select the renderer for sprite-sheet content.
- Create: `PetDeskTests/PetLayerRendererTests.swift`.
- Update: `project.yml` only if XcodeGen does not include the new files through `PetDesk`.

- [ ] **Step 1: Define a testable layer configuration before creating the view.**

Add a pure configuration value with behavior equivalent to:

```swift
struct PetLayerAnimationConfiguration: Equatable {
  let frameCount: Int
  let frameDuration: TimeInterval
  let isPaused: Bool
}
```

Test that an empty frame list is safe, duration is clamped to `1.0/30.0...0.20`, and pause state is represented without creating a repeating animation. Run the focused test and confirm it fails before adding the configuration.

- [ ] **Step 2: Implement `PetLayerRenderer` as an AppKit view.**

Use one backing `CALayer` with `contentsGravity = .resizeAspect`, transparent background, and a discrete `CAKeyframeAnimation(keyPath: "contents")`. Preloaded `CGImage` values are assigned to `values`, `keyTimes` are evenly spaced, and `duration` is `frameDuration * frameCount`. Set `repeatCount = .greatestFiniteMagnitude`, `calculationMode = .discrete`, and `isRemovedOnCompletion = false`.

The update method must be idempotent: do not replace the animation when frames, duration, pause state, and row are unchanged. When pausing, preserve the current Core Animation time by setting `layer.speed = 0` and `layer.timeOffset` to the converted current time. When resuming, restore `speed`, `timeOffset`, and `beginTime` using the standard paused-layer formula. Removing a sheet or receiving zero frames must remove the animation and clear `contents`.

- [ ] **Step 3: Bridge only the renderer inputs into SwiftUI.**

`PetLayerRendererRepresentable` receives prepared frames, `avatarSize`, `isPaused`, `cpu`, and `speedMultiplier`. Its `updateNSView` converts the prepared `NSImage`/`CGImage` list into the layer update call. It must not sample CPU, query permissions, read files, or choose a `PetState`.

- [ ] **Step 4: Keep static avatars on the existing low-cost path.**

In `PetView`, use the layer representable only when a sprite sheet has more than one prepared frame. Use the existing `Image` path for static imported photos, placeholders, and one-frame poses. Keep `OverlayEffectView` outside the renderer so sweat/smoke effects retain their existing state-machine inputs.

- [ ] **Step 5: Verify visual and lifecycle behavior.**

```bash
make generate
make test
make verify
```

Manual checks: show/hide the pet, cover it with another window, move between Spaces, change CPU load, switch rows, import a new pose, and quit/relaunch. Expected: no duplicate animation tasks, no stale frames after sheet replacement, and no animation while hidden or occluded.

- [ ] **Step 6: Commit the renderer as a separate change.**

```bash
git add PetDesk/Features/PetRender/PetLayerRenderer.swift PetDesk/Features/PetRender/PetLayerRendererRepresentable.swift PetDesk/Features/PetRender/PetView.swift PetDeskTests/PetLayerRendererTests.swift project.yml
git diff --cached --check
git commit -m "perf(render): animate sprite frames with calayer"
```

### Task 5: Reduce Custom Pose Preview Memory

**Files:**
- Create: `PetDesk/Features/Avatar/AvatarPreviewImageFactory.swift`.
- Modify: `PetDesk/App/AppEnvironment.swift:22,410-470,928-952`.
- Modify: `PetDesk/Features/Settings/SettingsView.swift:253-260`.
- Modify: `PetDeskTests/AppEnvironmentTests.swift` and create focused factory tests if needed.

- [x] **Step 1: Add a failing storage assertion.**

After importing multi-frame rows, assert that the settings preview contains exactly one image, `multiFrameCount(for:)` still reports the imported count, and transient full-resolution pose cells are released after assembly. This distinguishes UI preview storage from persistent frame-count metadata.

- [x] **Step 2: Implement a small preview factory.**

Create a 48x52-point thumbnail from the first `CGImage` using an `NSBitmapImageRep` or equivalent AppKit drawing context. The factory must return `nil` for invalid dimensions and must never log the source path or filename:

```swift
enum AvatarPreviewImageFactory {
  static func makePreview(from image: CGImage, size: CGSize) -> NSImage?
}
```

Store `[preview]` (one element for source compatibility with the current Settings view). Keep full-resolution pose cells only in the import/reassembly call scope; persistent playback uses the assembled spritesheet plus per-row frame counts.

- [x] **Step 3: Make restore and clear paths use the same policy.**

Update both import and persisted-avatar restore paths so they retain only the first preview. Clearing a row must remove the preview and all playback cells. Ensure replacing an avatar clears old preview objects before assigning the new map.

- [ ] **Step 4: Verify memory and UI behavior.**

```bash
make test
make verify
```

Open Settings, confirm the first-frame preview remains visible, import/clear/relaunch, then repeat the 10-minute RSS measurement. Record before/after peak RSS and note whether the decoded full spritesheet remains the dominant allocation.

- [ ] **Step 5: Commit the memory reduction.**

```bash
git add PetDesk/Features/Avatar/AvatarPreviewImageFactory.swift PetDesk/App/AppEnvironment.swift PetDesk/Features/Settings/SettingsView.swift PetDeskTests/AppEnvironmentTests.swift
git diff --cached --check
git commit -m "perf(avatar): retain one downsampled pose preview"
```

### Task 6: Prevent Redundant Animation Updates and Confirm Sampling Costs

**Files:**
- Modify: `PetDesk/Features/PetRender/PetLayerRendererRepresentable.swift` if input equality or update coalescing is incomplete.
- Modify: `PetDesk/App/AppEnvironment.swift` only if profiling proves redundant published updates.
- Modify: `PetDesk/Features/SystemLoad/SystemLoadMonitor.swift` only if profiling proves a one-second sampler is excessive; preserve one-second behavior unless tests prove a safe interval change.
- Test: `PetDeskTests/AppEnvironmentTests.swift` and `PetDeskTests/CoreServicesTests.swift` as applicable.

- [ ] **Step 1: Add a renderer update counter in test builds.**

Expose an internal counter or injectable sink, not a production log, and assert that repeated updates with the same row/frame list/interval/pause state do not recreate the `CAKeyframeAnimation`. Keep the counter unavailable to release diagnostics.

- [ ] **Step 2: Audit the one-second task for avoidable allocations.**

Use Time Profiler and Allocations to inspect `AppEnvironment.advanceOneSecond()`, `SystemLoadMonitor`, focus, usage stats, mood/energy, and diagnostics. Check that `DateFormatter` is shared, arrays are not copied on every tick, and no `NSImage` is constructed from `body`. Only make a code change when a trace identifies a repeated allocation with measurable cost; add a focused regression test before the change.

- [ ] **Step 3: Keep CPU sampling and animation cadence independent.**

The sampler may remain at one sample per second because it also drives thermal/state policy. Animation speed updates only when the sampled average changes; it must never create a second sampler or a per-frame Mach call. If a longer interval is empirically safe, change the injected default and update state-machine timing tests in the same commit.

- [ ] **Step 4: Commit only evidence-backed cleanup.**

```bash
make test
make lint
make verify
git add PetDesk/Features/PetRender/PetLayerRendererRepresentable.swift PetDesk/App/AppEnvironment.swift PetDesk/Features/SystemLoad/SystemLoadMonitor.swift PetDeskTests/AppEnvironmentTests.swift PetDeskTests/CoreServicesTests.swift
git diff --cached --check
git commit -m "perf(app): coalesce redundant animation updates"
```

Do not create this commit if the audit finds no measurable redundant work; record the no-change result in the session handoff instead.

### Task 7: Documentation, Profiling, and Release Gate

**Files:**
- Modify: `docs/architecture/overview.md` with the SwiftUI/AppKit renderer boundary and frame-cache ownership.
- Modify: `docs/debugging/runbook.md` with pause-layer, stale-frame, multi-Space, and Instruments commands.
- Modify: `docs/testing/test-plan.md` with static/one-frame/eight-frame performance scenarios and 30-minute stability checks.
- Create: `docs/performance/petdesk-optimization-results-2026-08.md`.
- Create: the timestamped session generated by `make handoff-new AGENT=claudecode TASK=performance-optimization`.
- Modify: `docs/agent-handoff/CURRENT.md` after re-reading it immediately before the edit.

- [ ] **Step 1: Run the complete verification gate.**

```bash
make generate
make test
make lint
make verify
make handoff-check
```

Expected: all commands pass. If Xcode-only profiling is unavailable, record the exact unavailable template or attachment error and retain the available `ps`/Time Profiler evidence.

- [ ] **Step 2: Repeat measurements with identical scenarios.**

Run the baseline script for 600 seconds for all three scenarios, then run a 30-minute stability session. Capture Release CPU average/peak, RSS average/peak, frame rate cap, and whether the animation is paused while occluded. Compare against `docs/performance/petdesk-baseline-2026-08.md`.

- [ ] **Step 3: Review privacy and binary impact.**

Confirm logs contain no paths, filenames, image data, or notification bodies. Run a resource and symbol audit; do not change `public` visibility merely for size unless the symbol is not part of the package/test contract. Confirm no generated project, DerivedData, trace, or user settings are staged.

- [ ] **Step 4: Create the immutable Claude Code handoff.**

```bash
make handoff-new AGENT=claudecode TASK=performance-optimization
```

Replace every generated placeholder with exact commands/results, changed files, commit hashes, skipped checks, confirmed risks, and ordered next actions. Obtain the generated filename with `SESSION_FILE=$(ls -t docs/agent-handoff/sessions/*-claudecode-performance-optimization.md | head -1)`, re-read `docs/agent-handoff/CURRENT.md`, link that file, then run `make handoff-check` again.

- [ ] **Step 5: Commit documentation and handoff separately from code.**

```bash
SESSION_FILE=$(ls -t docs/agent-handoff/sessions/*-claudecode-performance-optimization.md | head -1)
git add docs/architecture/overview.md docs/debugging/runbook.md docs/testing/test-plan.md docs/performance/petdesk-optimization-results-2026-08.md docs/agent-handoff/CURRENT.md "$SESSION_FILE"
git diff --cached --check
git commit -m "docs(performance): document optimization results and handoff"
git status --short --branch
```

The final status must show only the intentional branch state and the pre-existing untracked `picture.png`.

## Final Review Checklist

- [ ] `AnimatedAvatarView` no longer requests a 10ms timeline interval.
- [ ] `isPetAnimationPaused` reaches the renderer and produces zero animation work while hidden/occluded.
- [ ] Frame images are prepared once per sheet/row/frame-count change and reused during playback.
- [ ] `CALayer` updates are idempotent and do not create a new repeating animation every SwiftUI body update.
- [ ] CPU sampling remains at most once per second and is independent of frame playback.
- [ ] Settings keeps one downsampled preview per custom row; full-resolution playback data is not duplicated unnecessarily.
- [ ] No force unwrap, `try!`, `as!`, private API, OCR, SMC access, or privacy-sensitive logging was added.
- [ ] `make test`, `make lint`, `make verify`, and `make handoff-check` have exact recorded results.
- [ ] Baseline and post-change Release measurements are comparable and stored in `docs/performance/`.
- [ ] Claude Code receives this plan plus the latest handoff session before touching production code.
