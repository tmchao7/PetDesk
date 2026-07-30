# Architecture Overview

PetDesk uses AppKit for desktop window behavior, SwiftUI for rendering and controls, and a pure Swift reducer for behavior. `project.yml` is the Xcode project source of truth. `Package.swift` compiles the core and an AppKit/SwiftUI check target when full Xcode is unavailable.

## Data Flow

```text
MachCPUSampler / UserIdleMonitor / Notification adapter
                         |
                    PetEvent stream
                         |
                   AppEnvironment
                         |
                  PetStateMachine
                         |
                    PetSnapshot
                         |
             PetView / menu / diagnostics
```

Feature adapters own system calls. `AppEnvironment` owns cancellable tasks and orchestration. `PetStateMachine` is deterministic and contains no AppKit or SwiftUI. Views receive snapshots and commands; they do not sample hardware or read files.

`AvatarRepository` validates and downscales imported files before copying them into Application Support. `PetWindowController` owns the `NSPanel`, persistence, screen clamping, and hit-test regions. Diagnostics retain only the newest 200 sanitized events in memory.
