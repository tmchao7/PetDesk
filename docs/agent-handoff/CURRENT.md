# Current Agent Handoff

- Status: ready
- Active owner: claude code
- Updated: 2026-08-05T15:06:27+0800
- Branch: `docs/performance-followup-research`
- Latest implementation commit: `8ab44a6`
- Latest session: [codex external performance research](sessions/2026-08-05-1506-codex-external-performance-research.md)

## Active Objective

Continue PetDesk from `main` after the research-only handoff branch is recorded. Performance optimization is implemented: timeline capped 5–30 FPS with explicit occlusion pause, `AnimationFrameStore` pre-sliced frames, `PetLayerRenderer` CALayer discrete playback, and one downsampled pose preview per row. Review fix `8ab44a6` aligns Core Animation keyTimes with frame values and removes fallback force unwraps. Open follow-up work remains around CPU-speed publication, pause/resume continuity, and 30-minute RSS attribution.

## Repository Snapshot

- PetDesk on `main`; `main` now includes the performance review fix and handoff commits. `origin/main` is two commits behind and has not been pushed.
- Shipped: todo, usage stats, pet size + animation speed, bubble quick actions, avatar editor, spritesheet pet (programmatic + pose import + multi-frame), AI pose provider (off by default), mood/energy, drag shelf, **performance optimization** (frame cap/pause/preload/CALayer/preview memory).
- Docs: architecture, runbook, test-plan updated with renderer boundary and performance scenarios; baselines + results in `docs/performance/`.

## Latest Verification

- `make verify`: TEST SUCCEEDED after the review fix (106 unit tests, 7 UI tests, Debug/Release builds, CoreChecks).
- `make lint`: passed.
- Review focused renderer test: 5 tests passed.
- Optimized Release measurements remain static 1.09% CPU, single 0.72%, eight-frame 0.92% for 60s; the recorded 30-minute run averaged 2.06% CPU and RSS climbed 120→131MB.

## Blockers

- Allocations/Energy templates remain unavailable under `xctrace`; RSS growth is not attributed. CPU-paced CALayer speed is not currently proven because CPU-only changes are publication-gated, and `--demo-state focusing` filters later system-metric events.

## Next Actions

1. Claude Code implements the CPU timing signal and renderer transition tests from the follow-up prompt, using the external references in the latest session.
2. Run `make test`, `make lint`, and `make verify` after each coherent fix.
3. Use Instruments GUI Allocations for 30–60 minutes with Diagnostics closed and an imported 8-frame pose.
4. Add a pinned animation benchmark that changes CPU input without changing PetState.
5. Review redundant Package.swift entries and stale 100 FPS documentation.

## Working Rules

- Read the linked session before changing code.
- Preserve unrelated work and do not rewrite historical session files.
- Record exact verification evidence; do not convert skipped checks into success claims.
