# System Integrations

## CPU and Thermal State

`MachCPUSampler` reads aggregate host ticks and computes load from successive deltas. The first sample and any counter rollback establish a new baseline. `SystemLoadMonitor` samples once per second and cancels its task when its stream terminates.

Only `ProcessInfo.thermalState` is used for thermal information. PetDesk never presents exact temperature or power.

## User Activity

`CGEventUserIdleSampler` uses the public combined-session idle duration. It does not install a keyboard hook or store input events.

## WeChat and QQ

macOS does not expose a stable public API for reading another app's notification source. The v1 probe therefore resolves to `unsupported(sourceApplicationUnavailable)` and does not request Accessibility permission. The adapter and deduplicator remain isolated for a future source-app-only implementation. OCR, message databases, raw notification text, and private APIs are prohibited.

## Login Item

The setting uses `SMAppService.mainApp`. Failure is shown locally and never blocks the pet.
