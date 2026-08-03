# Current Agent Handoff

- Status: ready
- Active owner: unassigned
- Updated: 2026-08-03T15:09:00+0800
- Branch: `feat/ai-pose-vision-animation`
- Latest implementation commit: `55fc41a`
- Latest session: [codex drag-jitter-fix](sessions/2026-08-03-1508-codex-drag-jitter-fix.md)

## Active Objective

Drag jitter/ghosting fixed: drag deltas now use NSEvent.mouseLocation (global screen coordinates) instead of event.locationInWindow, which was computed against the pre-move frame and fed window movement back into the delta, making the window oscillate.

## Repository Snapshot

- Feature branch `feat/ai-pose-vision-animation` (feature commits … `10bb580`, `55fc41a`); local `main` unchanged but still 2 commits ahead of `origin/main` with no upstream configured.
- Shipped: jitter-free dragging via screen-coordinate deltas; manual mouseDragged pet dragging (upper screen reachable); reminder bubble survives state-machine ticks (real display duration); unconstrained panel frame; configurable reminder display duration (1–120 s); edge flood-fill keying (interior white preserved); customizable reminder messages + live preview (DIY); per-state duration reminders + Settings intervals; pinned manual 摸鱼/放松 states (no auto switch-back); 99.8% pose framing window (no character-edge clipping); custom-pose state restore from spritesheet; density-guarded mass-window trimming; transparent native-aspect sprite rendering (card border removed); regenerated spritesheet; single-channel file import (avatar / spritesheet / pose) fixing the pose-import race; pose import outcome logging; build marker (`app-build.txt` + Settings footer) and `make run-app`; emoji overlays removed; static per-state display; per-state pose import (专注/摸鱼/休息) with thumbnails + confirmations; grid auto-normalization + error feedback; status-bar focus removed.
- Docs updated: architecture overview, product spec, debugging runbook, v1 plan, `docs/design/spritesheet-authoring.md` (copy-paste prompts).

## Latest Verification

- `make lint`: passed.
- `swift run PetDeskCoreChecks`: passed (includes new spritesheet-policy check).
- `swift build --product PetDeskAppCheck`: BUILD SUCCEEDED.
- `make test`: TEST SUCCEEDED — 81 XCTest + 7 XCUITest (commit `55fc41a`).
- `make verify`: passed (2026-08-03 15:09, commits `55fc41a` + `d01796d`).

## Blockers

- None.

## Next Actions

1. User: `make run-app`, drag the pet around and confirm no jitter/ghosting.
2. Optional later: re-enable micro-motion animation; extend pose import to all 8 rows; real-key trial of Plan C; add a “重置位置” menu item.
3. Push after owner approval: feature branch, then `main` (currently 2 unpushed docs commits).

## Working Rules

- Read the linked session before changing code.
- Preserve unrelated work and do not rewrite historical session files.
- Record exact verification evidence; do not convert skipped checks into success claims.
