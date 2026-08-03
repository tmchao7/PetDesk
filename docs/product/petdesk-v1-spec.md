# PetDesk v1 Product Specification

PetDesk is a quiet desktop companion for one user on an Apple silicon Mac running macOS 26. Its first-launch promise is simple: import an anime-style portrait and immediately get a floating companion that reacts to the computer and to voluntary focus sessions.

## Included

- Transparent floating pet across Spaces, with position restoration and limited click-through.
- PNG, JPEG, and HEIC avatar import up to 20 MB; saved as a downsampled 1024 px PNG.
- **Animated pet**: saving an avatar auto-generates a Codex-style 8×8 spritesheet (idle/walking/running/working/drinking/sleeping/happy/surprised with blinking and subtle micro-transforms); the pet plays frames per state. Falls back to the static avatar if generation fails.
- **Optional AI pose generation** (off by default): when configured with `PETDESK_AI_POSE_API_KEY` (and optional base URL/model), GPT Image 2 generates a canonical chibi pose from the avatar — and optionally lying-flat/running/reaching poses — which is chroma-keyed into the same 8×8 spritesheet. Any AI failure falls back to the local generator; the avatar image is transmitted only when this opt-in provider is configured.
- **User-made spritesheet import**: users can generate the whole 8×8 atlas with any online AI (Doubao/GPT/Gemini, Codex Pet tools, etc.) and upload it from Settings or the pet's right-click menu. The app accepts a standard 1536×1664 transparent sheet or any 1:1-style 8×8 grid (e.g., 1024×1024) with a uniform solid background, auto-chroma-keys and re-tiles it, then validates per-row content before switching playback. Failures show explicit error messages; no API key or cost involved.
- **Per-pose import (专注/摸鱼/休息)**: each bubble state can use its own single pose image imported from Settings (PNG/WebP, solid/transparent background, auto keying). One pose per state is enough — the app derives that state's animation frames programmatically; states without a custom pose keep the avatar's default look.
- CPU-driven tea, work, jog, and run states plus coarse thermal smoke.
- Sleep after five minutes of input inactivity.
- A 25-minute focus session that pauses after 60 seconds of user inactivity.
- A movement reminder after 60 active minutes, with Done and 10-minute snooze actions.
- **Bubble quick actions** (left-click the pet): today's todo (top 5, inline check-off) + 专注 / 摸鱼 / 放松 buttons — focus starts a session, slack-off nudges toward tea, relax forces a 15-second sleep (Zzz with animated moon).
- **Todo list**: add / check / delete items persisted to JSON; accessible from the pet context menu, status bar, and Settings.
- **Usage stats**: daily 专注 / 摸鱼 / 休息 durations accumulated from pet state, viewable per day (last 7 days with bars) from the context menu, status bar, and Settings.
- Pet size setting (小 / 中 / 大) that scales the pet, effects, and window.
- Manual quiet mode, menu-bar control, login-item setting, diagnostics, and launch arguments.
- A source-app-only notification extension point that is allowed to report unsupported.

## Excluded

PetDesk v1 does not provide notes, file storage, exact temperature or wattage, application blocking, message contents, contact identity, OCR, or private database access.

## Success Criteria

The pet remains useful without Accessibility permission, restores itself to a visible screen, transitions without CPU threshold flicker, never logs sensitive content, and stays around 1% idle CPU and 100 MB memory in a signed Release build.
