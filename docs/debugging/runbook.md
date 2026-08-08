# Debugging Runbook

Start with `make verify`. With full Xcode, launch from the generated `PetDesk` scheme. Without it, run `swift build --product PetDeskAppCheck` and `swift run PetDeskCoreChecks`.

Useful launch arguments:

```text
--demo-state sleeping|working|jogging|running|focusing
--fake-notification wechat|qq
--reset-window-position
```

Stream sanitized logs with:

```bash
log stream --style compact --predicate 'subsystem == "io.github.tmchao7.PetDesk"'
```

Use the Diagnostics window to copy the current state, CPU average, notification capability, window frame, and latest 200 sanitized events.

Review these hotspots first: duplicate AsyncStream tasks, counter rollback after sleep, state dwell and hysteresis, focus pause transitions, `NSPanel` retention, multi-screen coordinates, bubble hit-test regions, image decode size, and Accessibility behavior after OS or client updates.

## AI Pose Provider

AI pose generation is opt-in and disabled unless `PETDESK_AI_POSE_API_KEY` is set. Supported environment variables:

```text
PETDESK_AI_POSE_API_KEY       Bearer key (required to enable)
PETDESK_AI_POSE_BASE_URL      OpenAI-compatible base URL, default https://api.openai.com/v1
PETDESK_AI_POSE_MODEL         default gpt-image-2
PETDESK_AI_POSE_SIZE          default 1024x1024
PETDESK_AI_POSE_TIMEOUT       seconds, default 300
PETDESK_AI_POSE_EXTRA_POSES   1/true to also generate running/lying/reaching poses
```

The provider sends the cropped avatar to the configured endpoint, then chroma-keys the magenta background and assembles the 8×8 sheet locally. Any failure records `ai-pose-fallback` in diagnostics and falls back to the programmatic generator. The key is read from the process environment and never logged or persisted. The RunComfy CLI transport is not implemented; `PETDESK_AI_POSE_TRANSPORT=runcomfy` keeps the provider disabled.

## Spritesheet Coordinate System

The spritesheet spec uses a top-left origin (row 0 at the top). Empirically (2026-08-03, macOS 26 SDK), `CGImage.cropping(to:)` also treats y=0 as the visual top for both in-memory and PNG-loaded images, so frame crops must NOT be y-flipped. The checks in `Checks/main.swift` pin this mapping per animation row.

## Animation Pause

Multi-frame rows (frameCount > 1) play through `PetLayerRenderer` (discrete `CAKeyframeAnimation` on `contents`); the `TimelineView(.periodic(by: interval))` path in `AnimatedAvatarView` is only the fallback. Both honor `AppEnvironment.isPetAnimationPaused` (window hidden/occluded): no TimelineView is instantiated, and the layer is frozen via `speed = 0` + `timeOffset`. To debug CPU usage, hide the pet and confirm `isPetAnimationPaused` flips in Diagnostics state — a running layer animation or timeline while hidden means the pause flag is not reaching the renderer.

Known CALayer pitfalls:
- `CAKeyframeAnimation` with `contents` requires preloaded `CGImage` values; do not crop or wrap `NSImage` during playback (use `AnimationFrameStore`).
- Pause/resume must use the standard layer formula (`speed = 0; timeOffset = convertTime(now)` → `speed = 1; timeOffset = 0; beginTime = convertTime(now) - pausedTime`); resuming by restarting the animation causes a visible jump.
- `PetLayerRendererRepresentable` sets `pet.avatar` accessibility at the NSView level — SwiftUI accessibility modifiers do not reach `NSViewRepresentable` (XCUITest depends on it).

## Release Performance Baselines

```bash
make generate
xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Release \
  -derivedDataPath /tmp/PetDeskDerived build CODE_SIGNING_ALLOWED=NO
scripts/measure-petdesk.sh "/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app" 600 15
```

Time Profiler (available): `xcrun xctrace record --template 'Time Profiler' --launch <app> --time-limit 60s --output /tmp/pet.trace`. Allocations/Energy Log templates fail to attach under Xcode 26.6 `xctrace` — record the exact error, fall back to `ps` RSS samples, and use the Instruments GUI when available. Baselines and results live in `docs/performance/`.

## Per-Pose Import (专注/摸鱼/休息)

Settings → 头像 shows three per-state pose entries:

- 专注姿势 → working row (focus sessions);
- 摸鱼姿势 → drinking row (slack/tea);
- 休息姿势 → sleeping row (relax).

Each accepts PNG/WebP pose images (any size; solid or transparent background); 专注 additionally supports multi-select of **1–8 frames** (its row then loops as an animation whose speed follows the CPU load — see `docs/design/spritesheet-authoring.md` 用法三 for the Doubao prompt). `PoseCellProcessor.loadCell` removes the background with an edge flood-fill: only background pixels connected to the image border become transparent, so interior white parts (belly/face) are preserved — a plain chroma-key would punch them out; images with a real transparent background are used as-is. The bbox then keeps the row/column window containing the central 99.8% of strong-alpha subject mass, and the character is contain-fit and centered into a 192×208 cell. `AppEnvironment.importPose(row:from:)` stores `[AnimationRow: [CGImage]]` and reassembles via `SpriteSheetGenerator.generate(fromRowFrames:fallbackCell:)` — user frames fill columns 0..<N, remaining columns use the avatar base cell (restart sync recovers the exact frame count). The assembled sheet is saved to `spritesheet.png`, so custom poses survive restart; importing a new avatar clears custom poses. Importing a pose before any avatar exists returns “请先设置头像”.

Feedback: each pose row shows a first-frame thumbnail plus a `×N` frame badge for multi-frame rows, the button changes to 更换…/清除, and import/clear show a confirmation alert. The full-sheet import entry (导入精灵图) was removed in the v1 trim — poses are imported only through the per-state buttons (专注/摸鱼/休息).

State representation: the keyboard / tea-cup / Zzz emoji overlays are removed. States are shown by the pet image itself — the imported pose when set, otherwise the avatar default. If a state still shows an emoji instead of the pet changing, the running app is an old build (check that Settings shows the 专注姿势/摸鱼姿势/休息姿势 rows).

## Drag Shelf 拖出（暂存托盘 → Finder/微信/QQ）

- 拖入：拖到宠物或托盘面板都接收文件/文件夹 URL，只存**原始路径**（`AppEnvironment.addShelfItems`），不复制文件。若原文件被删除，拖出会得到失效文件——这是设计（托盘是暂存，不是仓库）。
- 拖出：每行是 AppKit `ShelfRowView`（整行 `NSDraggingSource`）。拖到桌面/微信/QQ 失败时，先确认跑的是新构建——旧构建把拖拽视图放在 SwiftUI 行的 `.background`，行内容吞掉鼠标事件，拖拽从未启动。
- 拖拽 pasteboard 必须携带真实 `file://` 路径（`ShelfDragOutPasteboard` 的 `public.file-url`），绝不能用 SwiftUI `.onDrag`/Transferable 的临时容器副本（`com.apple.SwiftUI.Drag-*`），微信/QQ 等按 URL 消费的 app 会拒绝或读不到。
- 微信/QQ 还读旧式 `NSFilenamesPboardType`（路径数组）。拖拽写入器直接用文件的 `NSURL`（`makeWriter`），AppKit 自动生成 file-url + filenames 完整类型集，与 Finder 拖拽等价；`NSPasteboardItem` 无法携带 filenames 类型（非法 UTI），所以基于 item 的拖拽对 IM 目标无效。
- 移动/复制/废纸篓（Dropover 式）：`sourceOperationMask = [.copy, .move, .delete]`，Finder 同盘给 `.move`、跨盘给 `.copy`，微信/QQ/邮件只收 `.copy`，废纸篓给 `.delete`（源移入废纸篓、可恢复）。`.move`/`.delete` 时源在 `endedAt` **延迟 ~1s** 清理原文件并移出托盘（给目标读取时间）；若立即删除会与 Finder 异步读取竞态 → 目标端报"意外错误（错误代码-8058）"。
- 多选：单击=单选、Command+单击=切换、Shift+单击=从锚点连选；拖已选中的行=整组拖出（多 `NSDraggingItem`），拖未选中的行=只拖该行。选择是托盘面板的临时 UI 状态（`ShelfSelection`），重启不保留。

## Verifying You Are Running the New Build

Every launch writes a marker file:

```bash
cat ~/Library/Application\ Support/PetDesk/app-build.txt
# expect: pose-import-v2 <today's date>
```

Settings → 关于 also shows `构建：pose-import-v2`. To build and launch the freshly built app without Xcode:

```bash
make run-app
```

This kills any running PetDesk instance, rebuilds the Debug app, and opens it. After importing a pose, `~/Library/Application Support/PetDesk/spritesheet.png` must change its timestamp to today — otherwise the running app did not include the pose-import code.

Every pose-import outcome is logged to the `avatar` category (`AppLog.avatar`) and recorded in the Diagnostics window (`pose-imported`, or the failure message), so a failed Settings import can be identified from the Diagnostics window after an attempt.

For generation guidance and copy-paste prompts, see `docs/design/spritesheet-authoring.md`.

## Xcode Target Identity Conflicts

If Xcode reports that multiple targets produce the same `.swiftmodule` or `.xctest` output, run:

```bash
make generate
zsh scripts/check-xcode-target-identities.sh
```

`Config/Base.xcconfig` is shared by the app and both test targets, so it must not define
`PRODUCT_NAME` or `PRODUCT_BUNDLE_IDENTIFIER`. Target identities belong in `project.yml`.
Disabling module emission or splitting `build-for-testing` from `test-without-building` does not
fix a shared output identity.

The shipping app enables Hardened Runtime in its target settings. Test bundles intentionally do
not inherit it so Xcode's locally signed macOS UI test runner can load the UI test bundle without
a Team ID mismatch. Do not pass `CODE_SIGNING_ALLOWED=NO` to the Xcode test action.
