# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-05T15:40:41+0800
- Agent: codex
- Role: debug and code review
- Objective: animation speed pause review
- Status: complete
- Branch: docs/review-animation-speed-pause
- Starting commit: 420ab9a
- Ending commit: 420ab9a (review-only; handoff documentation pending commit)

## Context Read

Read `AGENTS.md`, `CLAUDE.md`, `docs/agent-handoff/CURRENT.md`, the latest
`claudecode animation-speed-and-pause-fix` session, the performance plan,
architecture/state-machine/product documents, and the merged commit `3f3294f`.
Confirmed `picture.png` is pre-existing and untracked.

## Work Performed

Reviewed the CPU speed signal, CALayer renderer transition logic, SwiftUI
bridge, fallback TimelineView, and focused tests. No production code was
changed in this session. Ran a standalone QuartzCore timing experiment to
compare direct `layer.speed` changes with a time-preserving update.

## Decisions

1. Keep `PetSnapshot.displayEquals` gating unchanged and keep CPU speed as a
   low-frequency signal.
2. Treat playback-speed changes as timing transitions: capture the current
   layer-local time, set `timeOffset` and `beginTime` around the transition,
   then apply the new `speed`. A direct speed assignment is not continuous.
3. Replacing images while paused may intentionally reset the new content to
   frame zero; this is acceptable if documented and tested through resume.
4. User animation-speed preference changes must update the independent speed
   signal, including while a manual state suppresses system metric events.

## Verification

Fresh verification in this sandbox:

- `xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -derivedDataPath /tmp/PetDeskBuildReview -configuration Debug build CODE_SIGNING_ALLOWED=NO`: `BUILD SUCCEEDED`.
- `make lint`: passed.
- `make test`: failed before tests because the sandbox cannot write the
  default user DerivedData/log directories.
- A retry with `/tmp` DerivedData built successfully but the test runner could
  not communicate with `testmanagerd` because of sandbox restrictions.
- `swift run PetDeskCoreChecks` and a retry with `/tmp` caches were blocked by
  SwiftPM sandbox/module-cache restrictions.
- `xcrun swift` QuartzCore experiment reproduced the timing jump: after
  QA1673 resume, changing speed from 1 to 3 changed local time from about
  391412.66 to 1174237.98; a time-preserving update changed it by only
  microseconds.

The implementation session's historical `make verify` result remains recorded
in `2026-08-05-1520-claudecode-animation-speed-and-pause-fix.md`; it was not
repeated successfully in this sandbox.

## Review and Debug Findings

### [P1] Direct `layer.speed` changes break frame continuity

- Evidence: `PetDesk/Features/PetRender/PetLayerRenderer.swift:98-105` sets
  `animationLayer.speed` directly for every non-paused update. The resume path
  at `:161-170` first applies QA1673 with `speed = 1`, then the caller applies
  the requested CPU speed. Core Animation's local time is scaled around the
  existing `beginTime`, so both live speed changes and pause->resume at a speed
  other than 1 can jump forward/backward. The QuartzCore experiment above
  reproduces this.
- Fix: add a time-preserving playback-speed transition (RunCatNeo-style):
  capture `current = layer.convertTime(now, from: nil)`, set
  `timeOffset = current`, `beginTime = CACurrentMediaTime()`, then set the
  target speed. Store the desired speed while paused and apply it through the
  same transition after resume.
- Test: assert local time remains continuous across speed changes and
  pause->resume with speed 0.5/3.0; rebuild count alone is insufficient.

### [P2] Animation-speed preference does not refresh the independent signal

- Evidence: `PetDesk/App/AppEnvironment.swift:54-56` persists
  `animationSpeedMultiplier` but does not call `updateAnimationPlaybackSpeed()`.
  `PetDesk/App/AppEnvironment.swift:623-626` returns early for all manual
  states, so no later metric event refreshes the signal while focusing,
  drinking, or sleeping. `PetView.swift:54-60` consumes only the stale
  `animationPlaybackSpeed` for the CALayer path, while the fallback
  `AnimatedAvatarView` reads the multiplier directly.
- Fix: recalculate the independent speed signal when the preference changes,
  without re-enabling CPU-driven state changes; add a manual-state test.

### [P2] Speed-signal tests do not verify publication semantics

- Evidence: `PetDeskTests/AppEnvironmentTests.swift:719-746` claims the
  snapshot was not published but never subscribes to `$snapshot`; the test at
  `:838-860` covers that separately. `:748-770` compares values but never
  counts `$animationPlaybackSpeed` emissions.
- Fix: add Combine subscriptions/counters (or an equivalent test seam) so the
  tests prove one emission on a real speed change and zero on identical input.

### [P3] Renderer transition coverage is incomplete

- Evidence: `PetDeskTests/PetLayerRendererTests.swift:52-83` checks rebuild count
  and boolean state but not current timeline position or effective speed. There
  is no test for pause -> image replacement -> resume, nor for an empty-frame
  update arriving while paused.
- Fix: add deterministic timing seams/accessors and cover those transitions.

### RSS

The 120->131 MB / 30-minute RSS increase remains unattributed. No Instruments
GUI Allocations session was available in this review; it must not be labeled a
leak.

## Open Issues and Risks

1. Fix the P1 layer-speed transition on a separate `fix/` branch with focused
   failing tests first.
2. Fix the P2 preference-refresh path and strengthen the speed-signal tests.
3. Run `make test`, `make lint`, `make verify`; if sandbox restrictions remain,
   record the exact skipped commands and use the owner machine for final QA.
4. Run Instruments GUI Allocations for 30-60 minutes with Diagnostics closed
   and a real 8-frame pose.
5. Create the next immutable handoff and update `CURRENT.md` after fixes.

## Next Actions

1. Fix the P1 layer-speed transition on a separate `fix/` branch with focused
   failing tests first.
2. Fix the P2 preference-refresh path and strengthen the speed-signal tests.
3. Run `make test`, `make lint`, and `make verify`; record sandbox failures if
   the test runner remains unavailable.
4. Run Instruments GUI Allocations for 30-60 minutes with Diagnostics closed
   and a real 8-frame pose.
5. Create the next immutable handoff and update `CURRENT.md` after fixes.

## Git State

Branch `docs/review-animation-speed-pause`, based on `main` at `420ab9a`.
No production files were modified. `picture.png` remains untracked.
