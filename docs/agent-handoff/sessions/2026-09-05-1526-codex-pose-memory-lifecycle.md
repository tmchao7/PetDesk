# Agent Session Handoff

## Metadata

- Timestamp: 2026-09-05T15:26:30+0800
- Agent: codex
- Role: implementation
- Objective: pose memory lifecycle
- Status: complete
- Branch: fix/reminder-and-drag-smoothness
- Starting commit: 22bb5eb
- Ending commit: 6393ca1

## Context Read

- `docs/agent-handoff/CURRENT.md` and latest linked session `2026-09-05-1505-codex-lightweight-optimization.md`.
- `docs/product/petdesk-v1-spec.md`.
- `docs/architecture/overview.md` and `docs/architecture/state-machine.md`.
- `docs/development/git-workflow.md`.
- Active plan `docs/superpowers/plans/2026-08-05-petdesk-performance-optimization.md`.

## Work Performed

- Replaced persistent `customPoseCells` ownership with `customPoseFrameCounts` in `AppEnvironment`.
- Kept processed pose CGImages only for the import/reassembly call; after saving the assembled spritesheet, only frame counts, diagnostics, and one downsampled preview remain in the environment.
- Changed reassembly to reconstruct existing custom rows temporarily from the current spritesheet, so importing/replacing/clearing one row preserves other custom rows without retaining their full-resolution cells.
- Changed startup restore to scan row cells one at a time and retain only count plus first-frame preview.
- Added a regression test covering two custom rows, post-assembly release, restart restoration, and clearing one row while preserving the other.
- Updated architecture, performance result, and active performance-plan documentation.

## Decisions

- `avatarSpritesheet` is the long-lived source of custom-pose playback pixels; per-row frame counts are the long-lived metadata source.
- `retainedCustomPoseFrameCount` is DEBUG-only test instrumentation and must remain absent from release diagnostics.
- Reassembly updates observable pose metadata only after the new spritesheet is successfully saved, avoiding an in-memory state/file mismatch on save failure.

## Verification

- TDD red phase: the new test initially failed to compile because `retainedCustomPoseFrameCount` did not exist; after implementation it passed.
- Focused lifecycle test: 1/1 passed.
- Full `PetDeskTests`: 158/158 passed.
- Full `PetDeskUITests`: 7/7 passed.
- `make lint`: passed.
- `make verify`: passed, including handoff checks, CoreChecks, Debug/Release builds, 158 unit tests, and 7 UI tests.
- Release runtime sample after the change: `scripts/measure-petdesk.sh "/tmp/PetDeskPoseMemoryDerived/Build/Products/Release/PetDesk.app" 60 15` returned `avg_cpu_pct=.09`, `avg_rss_mb=122`, `peak_rss_mb=123` for the default startup scenario.
- `git diff --check`: passed before commit.

## Review and Debug Findings

- Default static Release RSS did not increase; this is a safety result, not a quantified eight-frame memory reduction because the sample did not import a real eight-frame pose through Settings.
- Existing warnings remain: SwiftPM reports two unhandled pose source files, and the compiler reports deprecated `onChange(of:perform:)` in `DragShelfView.swift`; neither is caused by this change.
- The current code still decodes the full spritesheet for playback; this is intentional and is the next bounded ownership floor unless the renderer/storage format changes.

## Open Issues and Risks

- A real Settings-imported eight-frame Release measurement and 30–60 minute RSS/Allocations profile remain outstanding.
- Dynamic CALayer shadow and independent one-second loops still need profiling before code changes.
- Drag Shelf full-path persistence still conflicts with the privacy rules and requires product approval.
- `docs/superpowers/plans/2026-08-05-petdesk-performance-optimization.md` Task 5 manual/UI measurement checkbox remains open because no manual Settings session was performed in this coding run.

## Next Actions

1. Owner manually import an eight-frame focus pose and compare Release RSS/CPU against the earlier 8-frame baseline.
2. If memory remains high, profile decoded spritesheet and Core Animation allocations with Instruments.
3. Decide the Drag Shelf privacy contract.
4. Consider standard SwiftUI Buttons and native interaction polish as a separate UI-focused change.

## Git State

- Branch: `fix/reminder-and-drag-smoothness`
- Latest implementation commit: `6393ca1 perf(avatar): release pose frames after assembly`
- Handoff documentation is pending as a separate commit.
- Pre-existing untracked `.mimosa/`, `.zcode/`, and `picture.png` remain untouched.
