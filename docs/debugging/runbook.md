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
