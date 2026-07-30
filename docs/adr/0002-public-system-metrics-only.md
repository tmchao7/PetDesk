# ADR 0002: Use Public, Coarse System Metrics

## Status

Accepted on 2026-07-30.

PetDesk uses Mach aggregate CPU ticks and `ProcessInfo.thermalState`. It does not use SMC access, privileged helpers, or invented temperature and wattage values. This keeps installation predictable and state labels honest.
