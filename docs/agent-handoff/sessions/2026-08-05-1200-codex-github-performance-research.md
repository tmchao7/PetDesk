# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-05T12:00:07+0800
- Agent: codex
- Role: performance research and architecture review
- Objective: github performance research
- Status: complete
- Branch: main
- Starting commit: 3952dd4
- Ending commit: 3952dd4

## Context Read

Read `AGENTS.md`, `CLAUDE.md`, `AGENT.md`, `docs/agent-handoff/CURRENT.md`, the
latest performance-review and git-push sessions, and `docs/development/git-workflow.md`.
Inspected the current animation, environment, system-load, avatar, and window
implementations before comparing public GitHub projects.

## Work Performed

Audited the high-frequency paths without changing production code. Compared
PetDesk with:

- RunCat Neo: `CAKeyframeAnimation` on a `CALayer` with preloaded `NSImage`
  frames; its source comment reports about 7-8% CPU for frame-swapping versus
  about 0.1% for layer animation.
- OpenPetsKit: per-frame timers based on declared frame durations and a
  prebuilt `PetSpriteFrameAsset` store containing `CGImage` and `NSImage`.
- Kyome22/menubar_runcat: CPU sampling every 5 seconds and a rescheduled frame
  timer, capped by a 0.2 second base interval.
- EvanJoDesktopPet: async tasks for discrete effects with long sleeps rather
  than a permanent high-frequency SwiftUI timeline.

Relevant public references are linked in the review response; no third-party
runtime dependency or source was added.

## Decisions

Treat the GitHub projects as design evidence, not code to copy. Keep PetDesk's
zero-runtime-dependency rule. The recommended next implementation is a native
AppKit/CALayer frame renderer, with a short-term fallback of capping the
Timeline schedule at 20-30 FPS and pre-caching frames.

## Verification

No tests were changed. Existing baseline from the prior review remains:
`make verify` passed with 93 unit tests, 7 UI tests, and Debug/Release builds;
`make lint` and `make handoff-check` passed. The prior independent Debug sample
was approximately 8.4-10.8% CPU (about 9.3% mean) and 131.6-131.7 MB RSS for
60 seconds with no observed growth. Allocations/Energy profiling remains
unavailable in this environment.

## Review and Debug Findings

High-confidence hotspot when a custom row has more than one frame:
`PetDesk/Features/Avatar/AnimatedAvatarView.swift:46-52` requests a 100 Hz
`TimelineView`, while `:107-130` keeps only one cropped `NSImage` and creates a
new crop/wrapper on frame changes. This can create a positive feedback loop:
high system CPU shortens the interval and causes more rendering work.

The explicit pause flag is currently not passed from `AppEnvironment` through
`PetView` into `AnimatedAvatarView`; hiding/occlusion therefore relies on
SwiftUI schedule behavior rather than an explicit stop.

The one-second system-load, idle, state, focus, and stats paths are periodic but
small compared with a 100 Hz render loop. Network/GPT pose work is import-time
only, and the current Accessibility notification source finishes immediately.

## Open Issues and Risks

RSS is above the roughly 100 MB target, but no leak is proven. The decoded
1536x1664 RGBA spritesheet is about 10.2 MiB; the base image, avatar image,
custom pose cells, and preview `NSImage`s add copies. `customPoseImages` stores
every thumbnail although Settings currently reads only `.first`.

The measured CPU/RSS sample was a Debug app, not a standalone Release build;
repeat the comparison in Release before setting a production budget.

## Next Actions

1. Add an isolated benchmark/test state for no custom pose, one custom frame,
   and an 8-frame custom row.
2. Implement explicit pause propagation and cap animation at 20-30 FPS as the
   low-risk experiment; measure CPU/RSS before and after.
3. Replace the hot path with pre-sliced frames plus `CALayer` contents
   animation, updating speed only when the one-second CPU sample changes.
4. Store only the first custom-pose preview thumbnail or generate previews
   lazily; repeat Allocations/Energy profiling with Instruments GUI.

## Git State

Branch: `main`, starting/published commit `3952dd4`; no production files were
changed. Working tree retains only the pre-existing untracked `picture.png`
plus this new handoff record before its documentation commit.
