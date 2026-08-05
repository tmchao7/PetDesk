# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-05T15:06:27+0800
- Agent: codex
- Role: external performance research
- Objective: external performance research
- Status: complete
- Branch: docs/performance-followup-research
- Starting commit: 8185ff0
- Ending commit: 032f22b

## Context Read

Read `AGENTS.md`, `CLAUDE.md`, `docs/agent-handoff/CURRENT.md`, the latest
performance handoff, `docs/development/git-workflow.md`, and the current
renderer/environment files. Confirmed the working tree contains only the
pre-existing untracked `picture.png` before this documentation change.

## Work Performed

Compared the remaining PetDesk risks with public implementations and
technical discussions:

- Apple QA1673 documents the standard `CALayer` pause/resume sequence using
  `speed`, `timeOffset`, and `beginTime`:
  https://developer.apple.com/library/archive/qa/qa1673/_index.html
- RunCatNeo's `RunnerLayer` preloads frame images into one
  `CAKeyframeAnimation` with `.discrete` timing and changes playback speed
  through a separate `setSpeed` path:
  https://github.com/runcat-dev/RunCatNeo/blob/d714e131eba7f23853c4bd51503e584b776d4b0f/LocalPackage/Sources/UserInterface/Views/RunnerBar/RunnerLayer.swift
- The older menubar_runcat CPU adapter computes Mach tick deltas when sampled,
  keeping sampling frequency separate from frame rendering:
  https://github.com/Kyome22/menubar_runcat/blob/master/Menubar%20RunCat/CPU.swift
- OpenPetsKit preloads cropped `CGImage` frames, keeps per-animation frame
  durations, and invalidates an actor cache using directory/file signatures:
  https://github.com/alterhq/OpenPetsKit/blob/main/Sources/OpenPetsKit/PetAnimation.swift
  https://github.com/alterhq/OpenPetsKit/blob/main/Sources/OpenPetsKit/OpenPetsPetAssetCache.swift
- Stack Overflow discussion reports that repeatedly starting SwiftUI
  `repeatForever` animations from timer/timeline updates can queue animations
  and drive CPU usage upward; it reinforces using a single idempotent animation
  and an explicit update path:
  https://stackoverflow.com/questions/79130716/cpu-use-increases-over-time-with-simple-swiftui-animation

No external source was copied into the repository and no runtime dependency
was introduced.

## Decisions

1. Keep `PetSnapshot.displayEquals` as the visual publication gate. Publish a
   separate low-frequency animation timing signal at the existing one-second
   metric cadence so CPU-only changes reach the renderer without per-frame
   SwiftUI invalidation.
2. Prefer a stable CA keyframe timeline plus a separate layer speed update,
   following RunCatNeo, instead of rebuilding the animation every CPU sample.
3. Treat pause/resume as a transition, not as an animation-content change.
   Use QA1673's formula and rebuild only when images or the actual animation
   content changes. If content changes while paused, install the new content
   and keep the layer paused at a defined first frame.
4. Keep the RSS rise unclassified until Instruments Allocations provides
   allocation evidence; do not call it a leak based on RSS alone.

## Verification

No production code or tests were changed. Read-only checks performed:

- `git status --short --branch`: clean except pre-existing `picture.png`.
- `rg` inspection of `AppEnvironment`, `PetView`, `PetLayerRenderer`, frame
  cache, diagnostics, and usage stats completed.
- External source retrieval succeeded for Apple QA1673, RunCatNeo,
  menubar_runcat, OpenPetsKit, and Stack Overflow API content.

`make test`, `make lint`, `make verify`, and Instruments were not rerun because
this session was research/documentation only; prior handoff evidence records
the merged fix verification and the unavailable Instruments CLI templates.

## Review and Debug Findings

1. CPU timing publication is currently missing: `latestCPU` is assigned in
   `AppEnvironment.swift:626`, is not `@Published`, and `displayEquals` omits
   `averageCPU`; `PetView.swift:54-61` therefore may retain stale
   `frameDuration` when only CPU changes.
2. Pause/resume is currently vulnerable to a first-frame reset:
   `PetLayerRenderer.swift:70-86` includes `isPaused` in `currentConfig`, so a
   pause or resume marks `needsAnimationUpdate`; the resume branch is bypassed
   by `startAnimation`, which installs a new timeline.
3. `customPoseCells` intentionally retains full-resolution frames for
   playback. It should be compared with `AnimationFrameStore` and Core
   Animation allocations during an Instruments GUI run before changing
   ownership or cache lifetime.
4. `--demo-state working` feeds a finite CPU burst and `focusing` ignores
   later system metrics; neither proves live CPU-to-animation speed updates.

## Open Issues and Risks

1. The 30-minute RSS rise is not yet attributed; an Instruments GUI run is
   required before classifying it as a leak.
2. No current benchmark holds a visual state while accepting controlled CPU
   samples, so CPU-to-speed behavior needs a debug-only harness.

## Next Actions

1. Claude Code implements the separate one-second animation timing signal and
   renderer speed/transition handling on a feature branch.
2. Add focused tests for CPU-only timing publication, pause/resume continuity,
   and replacing images while paused.
3. Run `make test`, `make lint`, `make verify`, and record exact results.
4. Run Instruments GUI Allocations for 30-60 minutes with Diagnostics closed
   and an imported 8-frame pose; attribute RSS growth before labeling a leak.
5. Add a debug-only pinned animation benchmark that accepts controlled CPU
   samples without changing the visual state.

## Git State

Branch `docs/performance-followup-research`; no production files changed.
The pre-existing untracked `picture.png` remains intentionally untouched.
The research record and `CURRENT.md` pointer are the only intended changes.
