# Current Agent Handoff

- Status: ready
- Active owner: unassigned
- Updated: 2026-08-03T10:09:00+0800
- Branch: `feat/ai-pose-vision-animation`
- Latest implementation commit: `32f8798`
- Latest session: [codex menu-focus-removal-import-entry](sessions/2026-08-03-1008-codex-menu-focus-removal-import-entry.md)

## Active Objective

Codex relay complete: status-bar focus controls removed (专注/摸鱼/放松 live in the pet bubble), and spritesheet import is now reachable from Settings and the pet right-click menu. Next is manual QA of the new import entry and the earlier animation/import paths.

## Repository Snapshot

- Feature branch `feat/ai-pose-vision-animation` (feature commits `e52cc38`, `ca70a72`, `d06800a`, `e383528`, `32f8798`); local `main` unchanged but still 2 commits ahead of `origin/main` with no upstream configured.
- Shipped: status-bar focus entry removed; spritesheet import in Settings + pet context menu; earlier: `SpritesheetImportPolicy`, `AvatarRepository.importSpritesheet`, `GPTImage2Provider` (Plan C), `VisionEyeBandLocator`, animation pause, row-crop/base-fit fixes.
- Docs updated: architecture overview (menu/bubble responsibilities), product spec, debugging runbook, review checklist, v1 plan.

## Latest Verification

- `make test`: TEST SUCCEEDED — PetDeskTests 66 + 6 XCUITests, 0 failures (commits `e383528`/`32f8798`).
- `make lint`: passed.
- `swift run PetDeskCoreChecks`: passed (includes new spritesheet-policy check).
- `swift build --product PetDeskAppCheck`: BUILD SUCCEEDED.
- `make verify`: pending (handoff record first).

## Blockers

- None.

## Next Actions

1. Run `make verify` and commit the handoff record (`docs(handoff)`).
2. Manual QA: status bar no longer starts focus; right-click pet → 导入精灵图 presents the file panel and imports a sheet; Settings entry still works; re-check import validation, playback mapping, restart persistence, blink, animation pause.
3. Optional: ship a template atlas or prompt guide for online-AI authoring; real-key trial of Plan C poses.
4. Push after owner approval: feature branch, then `main` (currently 2 unpushed docs commits).

## Working Rules

- Read the linked session before changing code.
- Preserve unrelated work and do not rewrite historical session files.
- Record exact verification evidence; do not convert skipped checks into success claims.
