# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-05T14:40:07+0800
- Agent: codex
- Role: performance optimization code reviewer
- Objective: performance code review
- Status: complete
- Branch: fix/performance-review
- Starting commit: 8ab44a6
- Ending commit: 8ab44a6

## Context Read

Read `AGENTS.md`, `CLAUDE.md`, `docs/agent-handoff/CURRENT.md`, the latest
`claudecode performance-optimization` session, the active performance plan,
the architecture/runbook/test-plan docs, `Package.swift`, measurement script,
and the renderer, frame-store, environment, diagnostics, and usage-stat files.
Reviewed `main` at `e372c1e`; work was performed on `fix/performance-review`.

## Work Performed

Audited the completed optimization without repeating the already shipped frame cap, explicit pause propagation, frame preloading, CALayer renderer, or preview downsampling. Ran the existing `make verify` before changes, then fixed two unambiguous issues: `PetLayerRenderer` generated one more `keyTime` than `values`, and `AnimatedAvatarView.imagePlaceholder` used two force unwraps. Added `PetLayerRendererTests.testKeyTimesMatchFrameCount`, removed the unused optional binding warning, and committed the fix as `8ab44a6 fix(render): align keyframe times and remove fallback unwraps`.

## Decisions

Keep exactly one key time per frame value; the repeating animation reaches the next cycle at the duration boundary and does not need an extra key time at `1.0`. Treat `latestCPU` as a separate render signal if CPU-paced CALayer speed is required; do not remove the existing snapshot publication gate without measuring its SwiftUI cost. Do not call the 30-minute RSS climb a leak without Allocations evidence.

## Verification

Passed before the fix: `make verify` (CoreChecks, Debug/Release builds, 106 unit tests, 7 UI tests). Passed after the fix: focused `xcodebuild test -project PetDesk.xcodeproj -scheme PetDesk -only-testing:PetDeskTests/PetLayerRendererTests CODE_SIGNING_ALLOWED=NO` (5 tests), `make test` (106 unit tests, 7 UI tests), `make lint`, and `make verify`. `git diff --check` passed before commit. Xcode emitted expected environment warnings about the linkd autoShortcut service; no test failed.

## Review and Debug Findings

### Findings requiring follow-up

- 🔴 `PetDesk/App/AppEnvironment.swift:625-639`, `PetDesk/Features/PetDomain/PetState.swift:51-59`, `PetDesk/Features/PetRender/PetView.swift:54-61`: `latestCPU` changes on every system metric but is not `@Published`, and `displayEquals` intentionally suppresses snapshot publication for CPU-only changes. Consequently `PetLayerRendererRepresentable.frameDuration` does not update while the displayed state remains unchanged; CALayer animation speed stays at the last rendered CPU value. Add a throttled published `animationFrameDuration`/render signal and test stable-state CPU changes without making per-frame SwiftUI updates.

- 🟡 `PetDesk/Features/PetRender/PetLayerRenderer.swift:67-84`: pause is part of `currentConfig`, so pause false -> true calls `pauseLayer`, but true -> false makes `configChanged` true and calls `startAnimation` instead of `resumeLayer`. The standard time-offset resume implementation at `:131-138` is therefore bypassed on the normal path and the animation resets to the first frame. A row/sheet change while paused also leaves the old animation attached behind the new model contents. Separate pause transitions from content/duration changes, remove or rebuild paused animations deliberately, and add a renderer lifecycle test.

- 🟡 `PetDesk/Features/Avatar/AnimationFrameStore.swift:26-61`, `PetDesk/Features/PetRender/PetView.swift:16-21`, `PetDesk/App/AppEnvironment.swift:160,468-519`: the cache and renderer retain cropped frame references while `customPoseCells` also retains imported full-resolution cells that are not consumed by the CALayer playback path. CoreGraphics may share backing storage, but this is not guaranteed. `PetView.layerFrameStore` has no explicit `onDisappear` clear (the SwiftUI fallback store does). Use Allocations to attribute this before deciding whether to derive cells from the sheet or clear the layer store explicitly.

- 🟡 `PetDesk/App/DiagnosticRecorder.swift:24-31`, `PetDesk/App/AppEnvironment.swift:625,643-646`: every one-second `systemMetrics` event creates a UUID/date/string diagnostic line, appends it with `removeFirst`, then publishes a copied 200-element array. This is bounded live memory but high allocation churn and a plausible contributor to RSS high-water behavior. Profile with Diagnostics closed; consider a fixed circular buffer or publishing only when the diagnostics window is observed.

- 🟡 `PetDesk/App/AppEnvironment.swift:603-610,1032-1036`: `--demo-state working` injects a finite CPU burst, then the real monitor can return the pet to idle. `--demo-state focusing` pins manual focus, but `handle` drops all later `systemMetrics` events at `:617-620`; it proves animation is present but cannot exercise CPU-to-frame-speed changes. Add a dedicated pinned animation benchmark mode or an injected sampler that accepts controlled CPU values.

### Lower-priority findings

- ⚪ `Package.swift:21,35-36,87,98-99`: directory exclusions/source entries make the new AppKit files compile, but the explicit `PetRender` entries are redundant with the directory entries. `make verify` and SwiftPM checks pass; simplify only with a focused generation check.
- ⚪ `PetDesk/Features/Avatar/AnimatedAvatarView.swift:8-11` and the product spec still describe 100 FPS although the implementation is capped at 30 FPS. Update comments/docs to prevent future performance regressions.

### Verified correct

- `AnimatedAvatarView.computeInterval` clamps 0% to 0.20s and 100%/large multipliers to 1/30s; existing tests cover the boundaries.
- `isPetAnimationPaused` is `@Published`, is set by show/hide/occlusion callbacks, and is passed into both render paths; no timeline is built for the multi-frame fallback while paused.
- `AnimationFrameStore` key includes sheet identity, row, and clamped frame count; it retains the active sheet to prevent pointer reuse and clears in `AnimatedAvatarView.onDisappear`.
- `AvatarPreviewImageFactory` draws a real 48x52 bitmap; import, restore, and clear paths retain at most one preview per row.
- No force unwrap/`try!`/`as!` remains in the reviewed production Swift after commit `8ab44a6`; logs inspected in the performance path contain categories, fixed messages, counts, and state values rather than paths, filenames, or notification bodies.

## Open Issues and Risks

The 30-minute RSS change from 120 MB to 131 MB is not enough to classify as a leak. The most plausible first profiling target is diagnostic array churn, followed by duplicated decoded pose/spritesheet storage and Core Animation/ImageIO caches. UsageStats writes occur every 30 seconds but operate on a small bounded JSON array and are transient; no evidence currently makes them the primary cause. Allocations/Energy templates were unavailable through `xctrace`, so attribution remains open.

## Next Actions

1. Fix or explicitly design the CPU animation-speed publication path; add a stable-state regression test.
2. Fix pause/resume transition handling and stale animation replacement; add a renderer lifecycle test.
3. Run Instruments GUI Allocations for 30--60 minutes with Diagnostics closed and with an imported 8-frame pose; compare live/allocation stacks for DiagnosticRecorder, customPoseCells, AnimationFrameStore, CALayer, and ImageIO.
4. Add a repeatable pinned animation benchmark that changes CPU input without changing PetState.
5. Reconcile redundant Package.swift entries and stale 100 FPS documentation only after the behavior fixes.

## Git State

Branch: `fix/performance-review`.

Fix commit: `8ab44a6 fix(render): align keyframe times and remove fallback unwraps`.

Working tree retains only the newly generated handoff record, the pending `CURRENT.md` update, and the pre-existing untracked `picture.png` until the documentation commit is created.
