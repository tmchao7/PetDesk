# Debugging Runbook

Start with `make verify`. With full Xcode, launch from the generated `PetDesk` scheme. Without it, run `swift build --product PetDeskAppCheck` and `swift run PetDeskCoreChecks`.

Useful launch arguments:

```text
--demo-state sleeping|working|jogging|running|focusing
--fake-notification wechat|qq
--reset-window-position
```

Stream sanitized logs with:

```bash
log stream --style compact --predicate 'subsystem == "io.github.tmchao7.PetDesk"'
```

Use the Diagnostics window to copy the current state, CPU average, notification capability, window frame, and latest 200 sanitized events.

Review these hotspots first: duplicate AsyncStream tasks, counter rollback after sleep, state dwell and hysteresis, focus pause transitions, `NSPanel` retention, multi-screen coordinates, bubble hit-test regions, image decode size, and Accessibility behavior after OS or client updates.

## AI Pose Provider

AI pose generation is opt-in and disabled unless `PETDESK_AI_POSE_API_KEY` is set. Supported environment variables:

```text
PETDESK_AI_POSE_API_KEY       Bearer key (required to enable)
PETDESK_AI_POSE_BASE_URL      OpenAI-compatible base URL, default https://api.openai.com/v1
PETDESK_AI_POSE_MODEL         default gpt-image-2
PETDESK_AI_POSE_SIZE          default 1024x1024
PETDESK_AI_POSE_TIMEOUT       seconds, default 300
PETDESK_AI_POSE_EXTRA_POSES   1/true to also generate running/lying/reaching poses
```

The provider sends the cropped avatar to the configured endpoint, then chroma-keys the magenta background and assembles the 8×8 sheet locally. Any failure records `ai-pose-fallback` in diagnostics and falls back to the programmatic generator. The key is read from the process environment and never logged or persisted. The RunComfy CLI transport is not implemented; `PETDESK_AI_POSE_TRANSPORT=runcomfy` keeps the provider disabled.

## Spritesheet Coordinate System

The spritesheet spec uses a top-left origin (row 0 at the top). Empirically (2026-08-03, macOS 26 SDK), `CGImage.cropping(to:)` also treats y=0 as the visual top for both in-memory and PNG-loaded images, so frame crops must NOT be y-flipped. The checks in `Checks/main.swift` pin this mapping per animation row.

## Animation Pause

The pet is in static mode (v1): no frame timer or 30 fps Timeline is running; the pet shows the current state row's base frame. `isPetAnimationPaused` (window hidden/occluded) remains wired for when animation is re-enabled. To debug CPU usage, hide the pet and confirm `isPetAnimationPaused` flips in Diagnostics state.

## Importing a User-Made Spritesheet

Settings → 头像 → 导入精灵图 (or right-click the pet → 导入精灵图) accepts PNG/WebP atlases generated elsewhere (online AI, Codex Pet tooling). Two accepted forms:

- a standard 1536×1664 sheet with an alpha channel; or
- any 8×8 grid whose width/height are both divisible by 8 (cells ≥64 px, e.g., 1024×1024 or 1728×2304) with a uniform solid background — the background is chroma-keyed from the four corners and each cell is contain-fit re-tiled into 192×208.

Validation mirrors hatch-pet's atlas rules, adjusted to this project's 8-row spec:

- PNG or WebP; the final sheet must have an alpha channel (auto keying handles uniform opaque backgrounds);
- each used frame per row must contain at least 50 non-transparent pixels (`SpritesheetImportPolicy.minUsedPixels`).
- grid lines must be clean: content crossing cell boundaries means the layout is not a usable 8×8 grid and the import is rejected with `invalidGrid`.

Row order is fixed: idle, walking, running, working, drinking, sleeping, happy, surprised. Used frame counts per row come from `AnimationRow.frameCount` (idle 6, walking 8, running 8, working 6, drinking 6, sleeping 6, happy 5, surprised 4); trailing cells in a row are never played. On success the sheet replaces `spritesheet.png` and playback switches immediately; on failure the previous sheet is kept and a Chinese error is shown in Settings.

Import feedback: the pet context-menu flow shows an alert with the exact failure reason (dimensions, grid layout, background, sparse cells); Settings shows the same message inline. If a generated sheet is rejected as `invalidGrid`, regenerate a cleaner 1:1 grid or use the single-avatar path instead.

## Per-Pose Import (专注/摸鱼/休息)

Settings → 头像 shows three per-state pose entries:

- 专注姿势 → working row (focus sessions);
- 摸鱼姿势 → drinking row (slack/tea);
- 休息姿势 → sleeping row (relax).

Each accepts one PNG/WebP pose image (any size; solid or transparent background). `PoseCellProcessor.loadCell` chroma-keys a uniform background from the four corners, trims to the subject, and contain-fits into a 192×208 cell. `AppEnvironment.importPose(row:from:)` stores the cell and reassembles the full 8×8 sheet, using the avatar base cell for rows without a custom pose. The assembled sheet is saved to `spritesheet.png`, so custom poses survive restart; importing a new avatar clears custom poses. Importing a pose before any avatar exists returns “请先设置头像”.

Feedback: each pose row shows an imported thumbnail, the button changes to 更换…/清除, and import/clear show a confirmation alert. Single-pose images imported through the full-sheet entry (导入精灵图) are rejected with an `invalidGrid`-style message that points to the per-state entry — make sure to use the per-state buttons (专注/摸鱼/休息) for single poses.

For generation guidance and copy-paste prompts, see `docs/design/spritesheet-authoring.md`.

## Xcode Target Identity Conflicts

If Xcode reports that multiple targets produce the same `.swiftmodule` or `.xctest` output, run:

```bash
make generate
zsh scripts/check-xcode-target-identities.sh
```

`Config/Base.xcconfig` is shared by the app and both test targets, so it must not define
`PRODUCT_NAME` or `PRODUCT_BUNDLE_IDENTIFIER`. Target identities belong in `project.yml`.
Disabling module emission or splitting `build-for-testing` from `test-without-building` does not
fix a shared output identity.

The shipping app enables Hardened Runtime in its target settings. Test bundles intentionally do
not inherit it so Xcode's locally signed macOS UI test runner can load the UI test bundle without
a Team ID mismatch. Do not pass `CODE_SIGNING_ALLOWED=NO` to the Xcode test action.
