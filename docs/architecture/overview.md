# Architecture Overview

PetDesk uses AppKit for desktop window behavior, SwiftUI for rendering and controls, and a pure Swift reducer for behavior. `project.yml` is the Xcode project source of truth. `Package.swift` compiles the core and an AppKit/SwiftUI check target when full Xcode is unavailable.

## Data Flow

```text
MachCPUSampler / UserIdleMonitor / Notification adapter
                         |
                    PetEvent stream
                         |
                   AppEnvironment
                         |
                  PetStateMachine
                         |
                    PetSnapshot
                         |
             PetView / menu / diagnostics
```

Feature adapters own system calls. `AppEnvironment` owns cancellable tasks and orchestration. `PetStateMachine` is deterministic and contains no AppKit or SwiftUI. Views receive snapshots and commands; they do not sample hardware or read files.

`AvatarRepository` validates and downscales imported files before copying them into Application Support. `PetWindowController` owns the `NSPanel`, persistence, screen clamping, and hit-test regions. Diagnostics retain only the newest 200 sanitized events in memory.

## Feature Modules

### Avatar & Animation

- `AvatarRepository` (actor): avatar PNG + **spritesheet PNG** storage in Application Support.
- `AvatarCropper` / `AvatarEditorView`: crop/zoom/display-mode editor; saving a cropped image auto-generates a spritesheet.
- `SpriteSheetSpec` + `SpriteSheetGenerator`: 8×8 grid (192×208 frames) with Codex-Pet-style micro-transforms (blink, 1-2px shifts, subtle rotation) per animation row. It accepts either the avatar image or per-row 192×208 base cells (`generate(fromRowCells:)`), so AI poses flow through the same deterministic assembly.
- `AIPoseProvider` (protocol): optional AI backend for richer poses; falls back to the programmatic generator.
- `GPTImage2Provider` (env-configured, **off by default**): calls an OpenAI-compatible `POST /images/edits` endpoint (`PETDESK_AI_POSE_API_KEY`, `PETDESK_AI_POSE_BASE_URL`, `PETDESK_AI_POSE_MODEL`, `PETDESK_AI_POSE_SIZE`, `PETDESK_AI_POSE_TIMEOUT`). One call generates a canonical chibi pose on a magenta background; `PoseCellProcessor` chroma-keys it into a transparent 192×208 cell. Default single-pose mode derives every animation row from the idle cell; `PETDESK_AI_POSE_EXTRA_POSES=1` adds running/lying-flat/reaching pose calls. Any failure or missing configuration falls back to the programmatic generator. The RunComfy CLI transport is not implemented yet; pointing the base URL at a compatible endpoint is supported.
- `VisionEyeBandLocator`: locates the blink overlay band with Vision face landmarks; `SpriteSheetGenerator` scales the band into the 192×192 base and falls back to the fixed y 60-70 band when no face is found.
- Per-row pose import (v1: 专注/摸鱼/休息): Settings lets the user import pose images per bubble state — working (专注, 1–8 frames), drinking (摸鱼), sleeping (休息). `PoseCellProcessor.loadCell` chroma-keys and fits each image into a 192×208 cell; `AppEnvironment.importPose(row:from:)` stores `[AnimationRow: [CGImage]]` and reassembles via `SpriteSheetGenerator.generate(fromRowFrames:fallbackCell:)` — user frames fill columns 0..<N without programmatic transforms, remaining columns use the avatar base cell (so restart sync recovers the exact frame count); default/AI rows keep the single-cell + micro-transform path. Custom poses persist via `spritesheet.png`; changing the avatar clears them.
- Multi-frame animation (performance-optimized): frames are **pre-sliced once** by `AnimationFrameStore` per (sheet, row, frame-count) into paired `CGImage`/`NSImage` arrays — playback does no cropping and no `NSImage` wrapping. Multi-frame rows (frameCount > 1) play through `PetLayerRenderer`, an AppKit `NSView` with a discrete `CAKeyframeAnimation` on `contents` (idempotent updates: same images/duration/pause does not rebuild the animation; pause freezes layer time via `speed = 0` + `timeOffset`). `PetLayerRendererRepresentable` is the minimal SwiftUI bridge (frames, size, pause, duration only). The CPU-driven frame duration is clamped to **5–30 FPS** (`interval = clamp(200ms / max(1, min(20, cpu% / 5)), 1/30…0.20)`), preventing CPU-positive feedback; `AppEnvironment.latestCPU` (non-@Published, closure-read) feeds the speed. Static avatars and one-frame poses keep the low-cost SwiftUI `Image` path; `AnimatedAvatarView`'s `TimelineView(.periodic(by: interval))` remains only as the non-CALayer fallback and honors `isPaused` (no timeline instantiated while hidden/occluded).
- Pose cell keying: `PoseCellProcessor` uses an edge flood-fill (4-connectivity, from the four image edges) to remove only background pixels connected to the border. Interior regions that share the background color (e.g. a white belly/face inside a colored outline) stay opaque — plain chroma-key used to punch them out. Images that already carry a transparent background are used as-is. The subject bbox then keeps the row/column window containing the central 99.8% of strong-alpha mass; the character is contain-fit and centered in the 192×208 cell.
- Transparent pet rendering: the floating window is a borderless `NSPanel` with `isOpaque = false` and a clear background. Sprite-based pets render the 192×208 frame at its native aspect ratio with no card border, so only the character is visible over the desktop; the rounded-rect card style is reserved for the fallback (non-sprite) avatar.
- Custom-pose state restore: on launch (or after importing a full spritesheet), `AppEnvironment` re-derives per-row custom poses by comparing each working/drinking/sleeping frame against the avatar base cell with a small pixel tolerance. This keeps Settings rows (thumbnails, 更换/清除) consistent across restarts and prevents clearing one row from dropping other imported poses.
- Manual state pinning: 专注 (focusing), 摸鱼 (drinkingTea) and 放松 (sleeping) all set a `manualState` override in `AppEnvironment`; while pinned, `systemMetrics` and `userIdleChanged` events are ignored so the pet stays in the user-chosen state until they pick another action. 专注 is display-pinned too: when the timed focus session completes, `handle` forces `baseState = .focusing` so the pet does not drift back to CPU/idle-driven 摸鱼/放松 (cancellation is only ever triggered by switching to 摸鱼/放松, which sets the new pin directly); `cancelFocus()` clears the pin and syncs the latest real idle duration back into the state machine.
- Duration reminders: `AppEnvironment` tracks the continuous duration of the user-pinned state (专注/摸鱼/放松, per-state minute thresholds from Settings) and renders the per-state message template (with `{minutes}`/`{m}` placeholders) via `reminderText(for:minutes:)`. At each threshold multiple it sets `snapshot.bubble = .stateDurationReminder(text)`; `PetWindowController` shows that bubble without activating the app, and `AppEnvironment` clears it after the user-configured display seconds (default 10) on the per-second tick. Settings previews the same rendered text with `ReminderPreviewView` (matching `PetBubbleView` styling).
- Reminder bubble persistence: `PetStateMachine.reduce` replaces `snapshot.bubble` on every event (including the per-second tick), which used to erase the reminder after ~1 s. `AppEnvironment` keeps `activeReminderText` + `reminderBubbleRemaining` and re-applies the bubble after each reduce until the configured display seconds elapse, without overriding other bubble types.
- Window dragging: `PetPanel.constrainFrameRect(_:to:)` returns the proposed frame unmodified (no visible-screen confinement), and `PetHitTestHostingView` moves the window in `mouseDragged` because SwiftUI gestures swallow `mouseDown` and `isMovableByWindowBackground` never fires on the pet body. Drag deltas use `NSEvent.mouseLocation` (global screen coordinates) rather than `event.locationInWindow`, which is computed against the pre-move frame and would feed the window position back into the delta, causing jitter/ghosting. The pet can be dragged anywhere, including the upper half of smaller displays; if dragged fully off-screen, the next launch restores and clamps it back.
- `AnimatedAvatarView`: static per-state fallback (imported pose if set, avatar otherwise); falls back to the static avatar when no spritesheet exists. Frame cropping uses the spritesheet's top-left origin directly — `CGImage.cropping` treats y=0 as the visual top in the current SDK (verified; do not re-add a y flip).
- Pose preview memory: Settings keeps **one downsampled 48×52 preview per row** (`AvatarPreviewImageFactory` true-downsampling; `NSImage(cgImage:size:)` only changed display size while retaining full-resolution data). Playback keeps full-resolution frames in `customPoseCells` only.

### Todo

- `TodoItem` model + `TodoStore` (actor) persisted as JSON (`todos.json`).
- `TodoView` window opened from the pet context menu, status bar, and the bubble.
- `AppEnvironment.todoItems` is the single source of truth; `incompleteTodoItems` exposes all pending items and the bubble lists them in a scrollable area (160 pt max, two-finger/scroll-wheel) with inline check-off.

### Usage Stats

- `DayStats` model + `UsageStatsStore` (actor) persisted as JSON (`usage-stats.json`).
- `AppEnvironment` accumulates seconds per base state (focusing/tea/sleep) every tick, batches writes every 30s, flushes on exit.
- `StatsView` window shows the last 7 days with per-activity bars.

### Drag Shelf

- Dropover-style 暂存托盘: the pet window and the shelf panel are both `NSDraggingDestination`s that forward dropped file/folder URLs to `AppEnvironment.addShelfItems` (paths only; the original files are never copied). `DragShelfStore` persists the path list in UserDefaults and filters dead paths on load.
- Each shelf row is a single AppKit `ShelfRowView` (NSView + `NSDraggingSource`, bridged via `NSViewRepresentable`) that owns the icon, filename, remove button, and right-click menu. The whole row body starts the drag-out from `mouseDragged` — a SwiftUI row with the drag view in `.background` is unreliable because the row's own content swallows the mouse events.
- Drag-out pasteboard (`ShelfDragOutPasteboard.makeWriter`) uses the file's `NSURL` directly as the `NSPasteboardWriting`, so AppKit produces the same type set Finder does: `public.file-url` (real `file://` path — no SwiftUI temp-container copies) plus `NSFilenamesPboardType` (path array) plus the Apple URL type. Finder reads `public.file-url`; WeChat/QQ and other IM targets read `NSFilenamesPboardType` — an `NSPasteboardItem` cannot carry the legacy type (not a valid UTI), so a plain item-based drag is rejected by IM apps. There is no 复制/移动 picker and no `.move` in the source mask: cross-app "move" requires the source to delete the original on drop, which races Finder's asynchronous read and makes the destination report "意外错误（-8058）". Drag-out is therefore pure copy (`sourceOperationMask = .copy`).
- Shelf rows support selection (state lives in a `ShelfSelection` store, not the state machine): plain click = single select, Command+click = toggle, Shift+click = range from the anchor; clicking a selected row defers deselection to mouse-up so a group can be dragged. Dragging a selected row drags the whole selection (one `NSDraggingItem` per file, fanned icons); dragging an unselected row drags only that file.

### Pet Window Interaction (AppKit layer)

- `PetPanel`: borderless non-activating `NSPanel`, `canBecomeKey = true`, `becomesKeyOnlyIfNeeded = false`; `showPet()` calls `makeKey()` so single clicks dispatch immediately (`acceptsFirstMouse = true`).
- `PetHitTestHostingView`: constrains clicks to the pet region when the bubble is hidden (click-through elsewhere); `bubbleVisible` is derived from **one combineLatest pipeline** of `quickActionsVisible` + `snapshot` — two separate sinks would race (snapshot publishes every second and clobbers the flag, breaking bubble hit-testing).
- Pet clicks use SwiftUI `onTapGesture` (reliable once hit-testing is correct); the bubble's action labels use `onTapGesture` too.
- Right-click context menu: 待办事项 / 使用统计 / 设置 / 隐藏桌宠.
- Animation pause: `PetWindowController` pushes visibility/occlusion into `AppEnvironment.isPetAnimationPaused` (hidden or covered windows pause). `PetView` then renders static content instead of a 30 fps `TimelineView`, `AnimatedAvatarView` gates its frame timer, and the sleeping moon float stops repeating — saving CPU while the pet is not visible.
- Auxiliary-window activation counting: `AppEnvironment.auxiliaryWindowCount` reference-counts visible auxiliary windows (settings/stats/todo/diagnostics); `auxiliaryWindowDidAppear()` switches to `.regular` + activates, `auxiliaryWindowDidDisappear()` demotes to `.accessory` only when the count reaches zero — so closing one of several open windows never breaks the others' Dock/Cmd-Tab presence.

### Windows & Scenes

`PetDeskApp` declares: `MenuBarExtra` (status bar), `Settings`, and named windows — `diagnostics`, `todo`, `stats`. Deep views open windows via relay closures (`openSettings`, `openDiagnosticsWindow`, `openTodoWindow`, `openStatsWindow`) wired in `wireRelays()` from the App-level `@Environment`, because `@Environment` values are unavailable inside context menus and MenuBarExtra.

The status-bar menu covers show/hide pet, todo/stats/diagnostics/settings, and quit. Focus start/cancel intentionally lives in the pet bubble (专注/摸鱼/放松) rather than the status bar.

## Persistence

| Path | Format | Owner |
|---|---|---|
| `Application Support/PetDesk/avatar.png` | PNG | AvatarRepository |
| `Application Support/PetDesk/spritesheet.png` | PNG (1536×1664) | AvatarRepository |
| `Application Support/PetDesk/todos.json` | JSON | TodoStore |
| `Application Support/PetDesk/usage-stats.json` | JSON | UsageStatsStore |
| UserDefaults | scalars (avatarDisplayMode, petScale, reminder settings) | AppEnvironment |

Writes to `todos.json` / `usage-stats.json` are serialized through a single
`pendingWrite` Task chain in `AppEnvironment` — each write awaits the previous
one, so rapid todo mutations and the 30s stats flush can never land out of
order and overwrite newer data with stale snapshots.
