# PetDesk v1 Product Specification

PetDesk is a quiet desktop companion for one user on an Apple silicon Mac running macOS 26. Its first-launch promise is simple: import an anime-style portrait and immediately get a floating companion that reacts to the computer and to voluntary focus sessions.

## Included

- Transparent floating pet across Spaces, with position restoration and limited click-through.
- PNG, JPEG, and HEIC avatar import up to 20 MB; saved as a downsampled 1024 px PNG.
- CPU-driven tea, work, jog, and run states plus coarse thermal smoke.
- Sleep after five minutes of input inactivity.
- A 25-minute focus session that pauses after 60 seconds of user inactivity.
- A movement reminder after 60 active minutes, with Done and 10-minute snooze actions.
- Manual quiet mode, menu-bar control, login-item setting, diagnostics, and launch arguments.
- A source-app-only notification extension point that is allowed to report unsupported.

## Excluded

PetDesk v1 does not provide Todo, notes, file storage, exact temperature or wattage, application blocking, message contents, contact identity, OCR, or private database access.

## Success Criteria

The pet remains useful without Accessibility permission, restores itself to a visible screen, transitions without CPU threshold flicker, never logs sensitive content, and stays around 1% idle CPU and 100 MB memory in a signed Release build.
