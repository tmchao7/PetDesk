# Test Plan

`PetDeskTests` covers state thresholds, hysteresis, event restoration, thermal overlays, focus completion, idle pause, reminder snooze, CPU tick rollback, avatar policy, screen clamping, notification deduplication, and ring-buffer capacity.

`PetDeskCoreChecks` mirrors critical assertions without XCTest so Command Line Tools-only machines can verify behavior. It is not shipped in the app.

`PetDeskUITests` launches deterministic demo states and verifies the pet remains accessible without Accessibility permission. Full Xcode is required for XCUITest.

`ShelfDragOutTests` locks the drag-out contract: the pasteboard carries the real `file://` path and an image content UTI, and the copy/move mask follows the user's picker. Cross-app drag-out to Finder/微信/QQ must be verified by hand — XCUITest cannot synthesize a drop into another app.

With full Xcode available, `make verify` validates unique target product/module identities, builds
the app, and runs both XCTest and XCUITest. The build-only action may disable signing, but the test
action must retain Xcode's local ad-hoc signing so the macOS UI test runner can load its bundle.

Before release, manually test display disconnect/reconnect, Spaces and full screen, wake from sleep, login-item launch, invalid and large images, 30-minute resource stability, quiet mode, and both notification capability states.

## Performance Scenarios

Measured on the same Apple Silicon Mac with a Release build (`scripts/measure-petdesk.sh`); baselines and results are recorded in `docs/performance/`.

| Scenario | Setup | Acceptance |
| --- | --- | --- |
| Static avatar | default avatar, idle | Release avg CPU < 1% or ≥50% below baseline; RSS stable |
| One-frame pose | 专注 pose, 1 frame | same as static (low-cost Image path) |
| Eight-frame pose | 专注 pose, 8 frames, working state | 10-min avg CPU < 2%; no CPU-positive feedback (frame rate capped 5–30 FPS) |
| Occlusion pause | cover pet window with another window | `isPetAnimationPaused` flips; zero animation work (no timeline, layer frozen) |
| Hidden pet | 显示/隐藏桌宠 → hidden | same as occlusion |
| Restart | import pose, quit, relaunch | frame count and preview restored; no stale frames after sheet replacement |
| 30-min stability | any scenario | RSS has no sustained growth |

Notes: 8-frame baselines require importing through the Settings flow (scripted sheets are not restored as custom poses by the launch sync); a scripted sheet measurement that renders statically must be reported as such, not as an animation baseline. Allocations/Energy templates may be unavailable under `xctrace` (record exact error; use Instruments GUI).
