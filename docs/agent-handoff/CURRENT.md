# Current Agent Handoff

- Status: ready
- Active owner: unassigned
- Updated: 2026-08-03T09:40:00+0800
- Branch: `feat/ai-pose-vision-animation`
- Latest implementation commit: `ca70a72`
- Latest session: [codex ai-pose-vision-animation](sessions/2026-08-03-0939-codex-ai-pose-vision-animation.md)

## Active Objective

Codex relay complete: optional v1 polish shipped on `feat/ai-pose-vision-animation` — GPT Image 2 pose provider (env-configured, off by default) behind AIPoseProvider, Vision eye-band locator, occlusion/hidden animation pause, and a spritesheet row-crop fix. Next is manual QA and an optional real-key AI trial.

## Repository Snapshot

- Feature branch `feat/ai-pose-vision-animation` (2 feature commits: `e52cc38`, `ca70a72`); local `main` unchanged but still 2 commits ahead of `origin/main` with no upstream configured.
- Shipped on top of v1: `GPTImage2Provider` (OpenAI-compatible HTTP, `PoseCellProcessor` magenta chroma-key, single-pose default + opt-in extra poses), `VisionEyeBandLocator`, animation pause when hidden/occluded, spritesheet crop orientation + base-fit fixes.
- Docs updated: architecture overview, product spec, debugging runbook, review checklist, v1 plan.

## Latest Verification

- `make test`: TEST SUCCEEDED — PetDeskTests 60 (4 new) + 6 XCUITests, 0 failures (commits `e52cc38`/`ca70a72`).
- `make lint`: passed.
- `swift run PetDeskCoreChecks`: passed (new eye-band / row-cell / pose-cell / provider / Vision checks).
- `swift build --product PetDeskAppCheck`: BUILD SUCCEEDED.
- `make verify`: pending (handoff record first).

## Blockers

- None.

## Next Actions

1. Run `make verify` and commit the handoff record (`docs(handoff)`).
2. Manual QA: re-import avatar → verify blink band position, per-state row mapping, motion quality, and animation pausing when hidden/occluded.
3. Optional: real-key trial of single- and multi-pose AI generation; tune prompts/chroma tolerance.
4. Optional: RunComfy CLI transport (binary not installed; HTTP base-URL override already supported).
5. Push after owner approval: feature branch, then `main` (currently 2 unpushed docs commits).

## Working Rules

- Read the linked session before changing code.
- Preserve unrelated work and do not rewrite historical session files.
- Record exact verification evidence; do not convert skipped checks into success claims.
