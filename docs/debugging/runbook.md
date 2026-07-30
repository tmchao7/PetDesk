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
