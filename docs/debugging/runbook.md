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

The pet animation (Timeline + frame timer) pauses when the pet window is hidden or fully occluded. To debug CPU usage, hide the pet or cover the window and confirm `isPetAnimationPaused` flips in Diagnostics state.

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
