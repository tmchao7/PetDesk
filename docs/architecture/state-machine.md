# Pet State Machine

The snapshot separates `baseState`, `transientState`, `effects`, and `bubble`. This prevents a notification from destroying the CPU/focus state it temporarily covers.

## Base State Rules

| Context | State | Effects |
| --- | --- | --- |
| Active focus | `focusing` | keyboard |
| Idle at least 5 minutes | `sleeping` | Zzz |
| CPU below 20% | `drinkingTea` | tea |
| CPU 20-60% | `working` | keyboard |
| CPU 60-80% | `jogging` | none |
| CPU at least 80% | `running` | sweat |

CPU uses a ten-sample moving average, five percentage-point hysteresis, and a five-second dwell. Serious or critical `ProcessInfo.thermalState` adds smoke without reporting a temperature.

Focus overrides idle and CPU. Idle overrides CPU. Transients such as notification startle, celebration, and stretching expire independently and restore the current base state. Notification and reminder transients last about 2.5 seconds; their actionable bubble may be cleared by a user command.
