# Test Plan

`PetDeskTests` covers state thresholds, hysteresis, event restoration, thermal overlays, focus completion, idle pause, reminder snooze, CPU tick rollback, avatar policy, screen clamping, notification deduplication, and ring-buffer capacity.

`PetDeskCoreChecks` mirrors critical assertions without XCTest so Command Line Tools-only machines can verify behavior. It is not shipped in the app.

`PetDeskUITests` launches deterministic demo states and verifies the pet remains accessible without Accessibility permission. Full Xcode is required for XCUITest.

Before release, manually test display disconnect/reconnect, Spaces and full screen, wake from sleep, login-item launch, invalid and large images, 30-minute resource stability, quiet mode, and both notification capability states.
