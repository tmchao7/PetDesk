# PetDesk v1 Product Specification

PetDesk is a quiet desktop companion for one user on an Apple silicon Mac running macOS 26. Its first-launch promise is simple: import an anime-style portrait and immediately get a floating companion that reacts to the computer and to voluntary focus sessions.

## Included

- Transparent floating pet across Spaces, with position restoration and limited click-through.
- PNG, JPEG, and HEIC avatar import up to 20 MB; saved as a downsampled 1024 px PNG.
- **State-based pet display**: saving an avatar auto-generates the 8×8 spritesheet (idle/walking/running/working/drinking/sleeping/happy/surprised), and the pet switches to the current state's base frame — imported per-state poses (专注/摸鱼/休息) or the avatar default — without blink/shake/micro-motion in the current static mode. **专注 multi-frame animation**: the working row can hold 1–8 user-imported frames that loop as an animation whose speed follows the CPU load (RunCat-style: ≈5 FPS idle, ≈100 FPS at full load); other states stay static. Falls back to the static avatar if generation fails.
- **Optional AI pose generation** (off by default): when configured with `PETDESK_AI_POSE_API_KEY` (and optional base URL/model), GPT Image 2 generates a canonical chibi pose from the avatar — and optionally lying-flat/running/reaching poses — which is chroma-keyed into the same 8×8 spritesheet. Any AI failure falls back to the local generator; the avatar image is transmitted only when this opt-in provider is configured.
- **Per-pose import (专注/摸鱼/休息)**: each bubble state can use its own pose image(s) imported from Settings (PNG/WebP, solid/transparent background, auto keying). 专注 accepts 1–8 frames in one multi-select import and loops them as a CPU-paced animation; 摸鱼/休息 take a single frame. States without a custom pose keep the avatar's default look. This is the only user-facing pose customization path (whole-atlas import removed in the v1 trim).
- CPU-driven tea, work, jog, and run states plus coarse thermal smoke.
- Sleep after five minutes of input inactivity.
- A configurable focus session (default 25 minutes) that pauses after 60 seconds of user inactivity; the Settings focus duration controls both session completion and the continuous-focus reminder.
- A movement reminder after 60 active minutes, with Done and 10-minute snooze actions.
- **Bubble quick actions** (left-click the pet): today's incomplete todo list (all items, scrollable with two-finger/scroll-wheel, inline check-off) + 专注 / 摸鱼 / 放松 buttons — all three pin the pet to that state until the user picks another action (real CPU/idle readings no longer switch it back, and completing/cancelling the timed focus session does not drift the pet back to 摸鱼/放松 either); 专注 starts a focus session. The state itself is shown by the pet image (imported pose or avatar default); the keyboard/tea-cup/Zzz emoji overlays have been removed.
- **State duration reminders**: Settings lets the user configure separate reminder intervals (minutes), a per-reminder display duration (seconds, default 10), and customize each reminder message for 专注 / 摸鱼 / 放松, with a live bubble-style preview (DIY). The 专注 interval is also the total duration of a manually started focus session; changing it during an active focus session restarts the session and reminder elapsed time from the change. Messages support the `{minutes}` placeholder (also `{m}`) which renders the current continuous session minutes; blank messages fall back to defaults such as “你已连续专注 25 分钟”. After the chosen state has been continuous for that interval, the pet shows the rendered text bubble; it stays for the configured display duration, then auto-dismisses, and repeats at each interval multiple. Reminders never switch the state or steal app focus.
- **Todo list**: add / check / delete items persisted to JSON; accessible from the pet context menu, status bar, and the pet bubble.
- **Usage stats**: daily 专注 / 摸鱼 / 休息 durations accumulated from pet state, viewable per day (last 7 days with bars) from the context menu, status bar, and Settings.
- Pet size setting (小 / 中 / 大) that scales the pet, effects, and window.
- Menu-bar control, login-item setting, diagnostics, and launch arguments.
- A source-app-only notification extension point that is allowed to report unsupported.

## Excluded

PetDesk v1 does not provide notes, file storage, exact temperature or wattage, application blocking, message contents, contact identity, OCR, or private database access.

## Success Criteria

The pet remains useful without Accessibility permission, restores itself to a visible screen, transitions without CPU threshold flicker, never logs sensitive content, and stays around 1% idle CPU and 100 MB memory in a signed Release build.
