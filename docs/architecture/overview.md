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
- User-imported spritesheets: Settings → 导入精灵图 (and the pet right-click menu) accepts a user-made PNG/WebP atlas. `SpritesheetImportPolicy` accepts either a standard 1536×1664 sheet with alpha or any 8×8 grid (width/height divisible by 8, cells ≥64 px) with a uniform solid background — the background is chroma-keyed and the grid is contain-fit re-tiled into 1536×1664. It then validates alpha and per-row used-frame content (≥50 non-transparent pixels, following hatch-pet's atlas rules). Failures show a clear alert/message instead of silent rejection; `AvatarRepository.importSpritesheet` persists to the same `spritesheet.png` used by playback, and the AI pose provider (Plan C) remains available as an opt-in alternative.
- Per-row pose import (v1: 专注/摸鱼/休息): Settings lets the user import one pose image per bubble state — working (专注), drinking (摸鱼), sleeping (休息). `PoseCellProcessor.loadCell` chroma-keys and fits each image into a 192×208 cell; `AppEnvironment.importPose(row:from:)` stores the cell and reassembles the sheet via `SpriteSheetGenerator.generate(fromRowCells:)`, falling back to the avatar base cell for rows without a custom pose. Custom poses are session-persisted via the assembled `spritesheet.png`; changing the avatar clears them.
- `AnimatedAvatarView`: **static per-state switching** (v1 simplification): shows the state row's base frame (imported pose if set, avatar otherwise) with no blink/shake/micro-motion; falls back to the static avatar when no spritesheet exists. Frame cropping uses the spritesheet's top-left origin directly — `CGImage.cropping` treats y=0 as the visual top in the current SDK (verified; do not re-add a y flip). The micro-transform animation pipeline remains in `SpriteSheetGenerator` for later re-enablement.

### Todo

- `TodoItem` model + `TodoStore` (actor) persisted as JSON (`todos.json`).
- `TodoView` window opened from the pet context menu, status bar, and the bubble.
- `AppEnvironment.todoItems` is the single source of truth; the bubble shows up to 5 incomplete items with inline check-off.

### Usage Stats

- `DayStats` model + `UsageStatsStore` (actor) persisted as JSON (`usage-stats.json`).
- `AppEnvironment` accumulates seconds per base state (focusing/tea/sleep) every tick, batches writes every 30s, flushes on exit.
- `StatsView` window shows the last 7 days with per-activity bars.

### Pet Window Interaction (AppKit layer)

- `PetPanel`: borderless non-activating `NSPanel`, `canBecomeKey = true`, `becomesKeyOnlyIfNeeded = false`; `showPet()` calls `makeKey()` so single clicks dispatch immediately (`acceptsFirstMouse = true`).
- `PetHitTestHostingView`: constrains clicks to the pet region when the bubble is hidden (click-through elsewhere); `bubbleVisible` is derived from **one combineLatest pipeline** of `quickActionsVisible` + `snapshot` — two separate sinks would race (snapshot publishes every second and clobbers the flag, breaking bubble hit-testing).
- Pet clicks use SwiftUI `onTapGesture` (reliable once hit-testing is correct); the bubble's action labels use `onTapGesture` too.
- Right-click context menu: 待办事项 / 使用统计 / 设置 / 隐藏桌宠.
- Animation pause: `PetWindowController` pushes visibility/occlusion into `AppEnvironment.isPetAnimationPaused` (hidden or covered windows pause). `PetView` then renders static content instead of a 30 fps `TimelineView`, `AnimatedAvatarView` gates its frame timer, and the sleeping moon float stops repeating — saving CPU while the pet is not visible.

### Windows & Scenes

`PetDeskApp` declares: `MenuBarExtra` (status bar), `Settings`, and named windows — `diagnostics`, `todo`, `stats`. Deep views open windows via relay closures (`openSettings`, `openDiagnosticsWindow`, `openTodoWindow`, `openStatsWindow`) wired in `wireRelays()` from the App-level `@Environment`, because `@Environment` values are unavailable inside context menus and MenuBarExtra.

The status-bar menu covers show/hide pet, quiet mode, todo/stats/diagnostics/settings, and quit. Focus start/cancel intentionally lives in the pet bubble (专注/摸鱼/放松) rather than the status bar; the pet's right-click menu also offers 导入精灵图 directly.

## Persistence

| Path | Format | Owner |
|---|---|---|
| `Application Support/PetDesk/avatar.png` | PNG | AvatarRepository |
| `Application Support/PetDesk/spritesheet.png` | PNG (1536×1664) | AvatarRepository |
| `Application Support/PetDesk/todos.json` | JSON | TodoStore |
| `Application Support/PetDesk/usage-stats.json` | JSON | UsageStatsStore |
| UserDefaults | scalars (quietMode, avatarDisplayMode, petScale) | AppEnvironment |
