# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-03T09:39:17+0800
- Agent: codex
- Role: implement optional v1 next steps (GPT Image 2 pose provider, Vision blink band, animation pause)
- Objective: AI pose vision animation
- Status: complete
- Branch: feat/ai-pose-vision-animation
- Starting commit: ca70a72
- Ending commit: (handoff commit follows; feature commits e52cc38, ca70a72)

## Context Read

- `AGENTS.md`, `CLAUDE.md`, `AGENT.md`, `docs/agent-handoff/README.md`
- `docs/agent-handoff/CURRENT.md` + latest session (docs-update-and-handoff) and phase3 session
- `docs/architecture/overview.md`, `docs/architecture/state-machine.md`, `docs/product/petdesk-v1-spec.md`
- Active plans under `docs/superpowers/plans/`, `docs/development/git-workflow.md`
- Codex Pet skill (aiskillstore marketplace, pinned commit) build_row pipeline; OpenAI image guide + images-edit reference (developers.openai.com reachable only via search snippets)
- Avatar feature sources, AppEnvironment, PetWindowController, PetView, Package.swift, Checks, tests

## Work Performed

1. `GPTImage2Provider` + `PoseCellProcessor` (new): OpenAI-compatible `POST /images/edits` multipart (reference PNG + prompt + `b64_json`), env-configured and **off by default** (`PETDESK_AI_POSE_API_KEY` etc.); magenta chroma-key (corner-sampled background, soft edge) → trim → contain-fit 192×208 cell. Single-pose default derives all 8 rows from the idle cell; `PETDESK_AI_POSE_EXTRA_POSES=1` adds running/lying/reaching pose calls. Any failure throws and AppEnvironment falls back to the programmatic generator (diagnostics: `ai-pose-fallback`).
2. `SpriteSheetGenerator` refactor: accepts per-row base cells (`generate(fromRowCells:)`); added injectable `eyeBandInSource`/`eyeBandInCell`; fixed `fittedBase` to a true 192×192 base (old 208-tall context squashed the avatar ~15 px vertically).
3. `VisionEyeBandLocator` (new): `VNDetectFaceLandmarksRequest` → eye-midpoint band in source pixel coords; nil on no face → fixed y 60-70 band fallback.
4. Animation pause: `AppEnvironment.isPetAnimationPaused` (default true), updated by `PetWindowController` on show/hide/occlusion; `PetView` renders static content when paused (no 30 fps Timeline), `AnimatedAvatarView` gates its frame timer, Zzz float stops repeating.
5. Fixed a latent spritesheet playback bug: `CGImage.cropping(to:)` treats y=0 as the **visual top** in this SDK (probed for both in-memory and PNG-loaded images), so the previous y-flip in `AnimatedAvatarView` displayed rows vertically mirrored (row r → row 7-r). Cropping now uses `frameRect` directly; Checks pin this mapping per row.
6. Docs: architecture overview, product spec, debugging runbook (AI env vars, coordinate system, animation pause), review checklist, v1 plan.

## Decisions

- HTTP OpenAI-compatible transport only; RunComfy CLI transport deliberately not implemented (binary not installed, input contract needs public URLs) — `PETDESK_AI_POSE_TRANSPORT=runcomfy` keeps provider disabled; base URL can point at compatible endpoints.
- Default one edit call per avatar save (cost control); extra poses opt-in.
- Eye-band locator protocol is not `Sendable`-constrained (synchronous, used only on the main actor).
- Kept the previous “y 60-70 fixed band” as fallback; do not re-introduce a y flip (coordinate behavior verified empirically 2026-08-03).

## Verification

- RED first: `swift run PetDeskCoreChecks` failed on new assertions before implementation.
- `swift run PetDeskCoreChecks`: all checks passed (includes new eye-band, row-cell, pose-cell, provider, Vision-locator checks).
- `swift build --product PetDeskAppCheck`: BUILD SUCCEEDED.
- `make test`: **TEST SUCCEEDED** — PetDeskTests 60 tests (4 new) and 6 XCUITests, 0 failures.
- `make lint`: passed (after `swift format --in-place` on changed files).
- `git diff --check`: clean.
- `make verify` still to run at handoff (after this record).

## Review and Debug Findings

- `CGImage.cropping` y=0 = visual top (context-made and PNG-loaded); existing flip comment and user-known-point #6 were wrong for this SDK — corrected in code, docs, and this record (original phase1-3 statements preserved).
- Old `fittedBase` used a 208-tall context and drew into 192×192, squashing the avatar to ~177 px tall; fixed.
- URLSession converts multipart bodies to `httpBodyStream`; Checks read the stream for assertions.
- Color management shifts pure magenta (#FF00FF) when drawn/decoded, so `PoseCellProcessor` samples the actual background from image corners instead of a fixed color.
- SwiftUI type inference needed `petTimeline()` as a separate `@ViewBuilder` for the paused/active branch.
- `Synchronization.Mutex` is non-Copyable and cannot be a struct stored property in XCTest fixtures; used an actor for the provider probe instead.

## Open Issues and Risks

- AI pose quality and multi-pose cost are unverified with a real API key (no key in this environment; provider is off by default).
- Manual QA still pending: import an avatar → verify blink band position, row mapping, motion quality, and that animation pauses when hidden/occluded.
- Vision band maps to the 192×192 base; lying/running pose cells reuse the same band heuristically.
- `main` is 2 commits ahead of `origin/main` from the previous docs session and still has no upstream configured; push still needs owner approval.

## Next Actions

1. Run `make verify` (full Xcode build + tests + handoff checks) and commit this record.
2. Manual QA with an imported avatar (blink position, per-state rows, occlusion pause, CPU before/after).
3. Optional: real-key trial of `GPTImage2Provider` single- and multi-pose modes; tune prompts/tolerance.
4. Optional: RunComfy CLI transport when the binary and input contract are available.
5. Owner-approved push of `main` (or this branch) to GitHub.

## Git State

- Branch: `feat/ai-pose-vision-animation`, based on local `main` (which is 2 commits ahead of `origin/main`; no upstream configured).
- Feature commits: `e52cc38` (feat(avatar)), `ca70a72` (feat(window)).
- Working tree clean before handoff record; `PetDesk.xcodeproj` remains generated/untracked.
