# Agent Session Handoff

## Metadata

- Timestamp: 2026-09-05T14:43:24+0800
- Agent: codex
- Role: read-only performance and product audit
- Objective: app audit
- Status: complete
- Branch: fix/reminder-and-drag-smoothness
- Starting commit: c4f73fc
- Ending commit: c4f73fc

## Context Read

- `docs/agent-handoff/CURRENT.md` and latest linked session `2026-09-05-1347-codex-reminder-drag-fix.md`.
- `docs/product/petdesk-v1-spec.md`.
- `docs/architecture/overview.md` and `docs/architecture/state-machine.md`.
- `docs/development/git-workflow.md`.
- Active performance plan `docs/superpowers/plans/2026-08-05-petdesk-performance-optimization.md`.

## Work Performed

- Performed a read-only source audit of AppEnvironment, state/focus/reminder flow, animation/frame caching, CALayer renderer, AppKit window/drag handling, Settings, and drag shelf.
- Ran `make test`; the 153 XCTest unit tests passed, but the complete command failed because `PetDeskUITests-Runner` was killed before bootstrapping/connection.
- Ran `make lint`; passed.
- No production code, generated project, or user files were modified.

## Decisions

- This session produces findings and a prioritized optimization roadmap only; implementation requires a separate approved design and TDD change.
- Treat the drag shelf's persisted file paths as a privacy/spec conflict requiring an explicit product decision before optimization work.
- Prioritize measurement-backed renderer/memory changes over speculative micro-optimizations.

## Verification

- `git status --short --branch` before audit: branch `fix/reminder-and-drag-smoothness`; pre-existing untracked `.mimosa/`, `.zcode/`, and `picture.png` only.
- `make test`: failed overall with XCUITest runner early unexpected exit; unit suite result was 153 tests, 0 failures.
- `make lint`: passed (`swift format lint --recursive PetDesk Checks PetDeskTests PetDeskUITests`).
- No `make verify` run in this session; the latest handoff records the same UI-runner environment failure.

## Review and Debug Findings

1. `PetView`'s CALayer path calls `AnimationFrameStore.preload(...).cgImages`, but that store always creates and retains an equal-sized `[NSImage]` array too. Multi-frame playback therefore retains UI wrappers that CALayer never uses. Split CG-only and SwiftUI frame preparation or make NSImage preparation lazy.
2. `AppEnvironment` retains `customPoseCells` while also retaining the complete `avatarSpritesheet`; imported pose pixel data is duplicated. Make row cells lazy/on-demand from the sheet or persist row metadata separately and release source cells after assembly.
3. `AppEnvironment.handle` returns early for `.systemMetrics` while `manualState` is set, so `latestCPU` and `animationPlaybackSpeed` freeze in pinned 专注/摸鱼/放松 states. This conflicts with CPU-paced animation and stale diagnostics. Keep behavior/state selection pinned while continuing low-frequency metric updates.
4. `PetWindowController` keeps a fixed 500×500 transparent panel for a roughly 148pt avatar. This increases transparent hit/occlusion surface and is not very native. Consider a smaller content-sized window with explicit margins or a separate bubble window, while preserving drag and bubble hit testing.
5. `PetLayerRenderer` uses a dynamic alpha shadow on a changing CALayer `contents` without a `shadowPath`; profile this as a likely per-frame compositing cost. Consider removing it, baking it into frames, or using a fixed path only if visual quality permits.
6. The app has a 1-second Task loop plus 1-second system-load and idle signal loops. They are independent and can wake the process three times per second even when hidden. A single shared heartbeat or pausing/coarsening nonessential sources while hidden could reduce wakeups, but must preserve focus/reminder timing and be benchmarked.
7. `DragShelfStore` persists full file paths and `ShelfRowView` reads/displays paths and file icons. This contradicts the repository privacy rule not to read, persist, or log imported filenames/paths. Resolve by removing/renaming the feature or explicitly revising the privacy/product contract; do not optimize this path before the decision.
8. The performance plan remains unchecked and there is no current post-2026-08 long-run evidence. The prior result documents ~0.06% idle CPU after cleanup, ~120MB RSS, and a 30-minute RSS climb to ~131MB; one-hour Allocations/Leaks and Energy Log attribution is still needed before claiming memory stability.

## Open Issues and Risks

- XCUITest runner early-exit remains an environment blocker, not evidence of a product regression.
- The manual-state CPU freeze may be intentional if pinned modes are meant to freeze animation speed, but current product text says focus animation speed follows CPU; add a regression test before changing behavior.
- Replacing the 500×500 panel or dynamic shadow can change hit testing, multi-Space behavior, and visual appearance; validate manually on multiple displays and with bubbles visible.
- Consolidating loops must not make state duration, focus pause, activity reminder, or usage statistics drift.
- The drag shelf privacy conflict may require a product/spec/architecture update rather than a technical optimization.

## Next Actions

1. Owner confirms whether CPU-paced animation should continue in manually pinned states and whether the drag shelf is in scope under the current privacy rules.
2. Add failing tests for pinned-state CPU/speed freshness and frame-store CG-only preparation; then implement the smallest approved changes.
3. Use Release Instruments/`xctrace` or equivalent to measure wakeups, dynamic shadow cost, allocation growth, and 30–60 minute RSS behavior.
4. Re-run `make test`, `make lint`, `make verify`, and `make handoff-check`; repeat manual multi-Space, occlusion, drag, bubble, and Settings checks.

## Git State

- Branch: `fix/reminder-and-drag-smoothness`
- Ending commit: `c4f73fc`
- Working tree before handoff: no tracked diff; pre-existing untracked `.mimosa/`, `.zcode/`, and `picture.png` remain untouched.
- Generated `PetDesk.xcodeproj` was regenerated by `make test` and remains uncommitted/generated.
