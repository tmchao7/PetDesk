# 全库 Code Review / Debug 清理报告（2026-08-03）

范围：三个并行审计（状态机不可达分支 / 死代码与无用功能 / 逻辑错误与防护），
按"逻辑错误修复、防护补齐、死代码与不可达分支删除、预留接口保留"处置。

## 一、删除：状态机不可达分支（走不到终点的状态代码）

| 删除项 | 说明 |
|---|---|
| `FocusCommand.pause` / `.resume` / `.relax` | 无任何产生方（AppEnvironment 只发 start/complete/cancel/showActivityReminder/snoozeActivity）；状态机对应分支一并删除 |
| `FocusSession.pause()` / `resume()` + `FocusPhase.paused` | pause/resume 无调用方，.paused 不可能出现 |
| `TransientPetState.greeting` | 无产生方；PetAnimState 映射同步删除 |
| `PetBubble.focusInvite` | 无产生方；PetBubbleView 的"开始专注？"分支简化 |
| `PetEffect.tea` / `.keyboard` / `.zzz` | 状态机每秒产生但从不渲染（emoji 覆盖移除后的遗留）；refreshEffects 只保留仍渲染的 sweat/smoke |
| `PetHitTestHostingView.bubbleRegion` | 生产代码从未读取（测试注释同步更新） |

## 二、删除：死代码 / 无用功能

| 删除项 | 说明 |
|---|---|
| `NotificationSource.unknown` | 全库零引用 |
| `NotificationUnsupportedReason.accessibilityDenied` | 全库零引用 |
| `AnimationRow.loopsPingPong` / `framesPerSecond` | 静态播放模式后零引用 |
| `RingBuffer.removeAll(keepingCapacity:)` | 零调用方 |
| `ScreenPositionStore.defaultFrame(size:screens:)` | 死重载（从未进入） |
| `AvatarCropState` struct | 零引用（文件保留 `AvatarDisplayMode` 枚举，重命名为 AvatarDisplayMode.swift） |
| `Checks/main.swift` 的 `makePNGData` | 零调用方 |

**保留（预留接口）**：`AIPoseProvider`/`GPTImage2Provider`（AI 姿态，opt-in）、
`VisionEyeBandLocator`（眨眼定位）、`LoginItemController`（开机启动）、
`AccessibilityNotificationPulseMonitor`（通知脉冲）、`NotificationPulseDeduplicator`。

## 三、修复：逻辑错误 / 防护

| 修复 | 问题 |
|---|---|
| 持久化写盘串行链（`AppEnvironment.pendingWrite`） | `flushUsageStats`/`persistTodo` 的 fire-and-forget Task 乱序落盘会**覆盖丢数据**（30s 批量与 stop 竞态、todo 快速勾选竞态）；现按触发顺序串行写入 |
| 启动统计合并 | 启动瞬间 tick 先累计、`loadUsageStats` 后到会**覆盖**已累计秒数；改为与磁盘值相加合并 |
| 写失败记录诊断 | `try?` 静默吞错（磁盘满/权限错误时用户无感知丢数据）；失败写入 diagnostics + AppLog |
| `PetStateMachine.record` 除零防御 | `sampleCount == 0` 时 0/0 → NaN 污染 averageCPU 与诊断报告 |
| `PetWindowController` scale 处理器死分支 | `petWindowSize` 恒为 500×500，setFrame 条件永不满足，删死分支 |

## 四、审计确认无问题（OK-by-design）

- 滞回分类、transient 过期账目、RingBuffer 线程安全、文件原子替换（APFS）、
  JSON 损坏降级、负时长防护、Task 生命周期均正确。
- `pausedForIdle`（专注中空闲 60s 计时暂停、视觉保持专注）是设计行为，
  OK-3 验证专注期间宠物不会睡回。
- `CGImage` 指针缓存 key 已有 `cachedFrameSheet` 强引用防护，地址复用风险已排除。

## 五、验证

- `swift run PetDeskCoreChecks`：passed（断言同步后）。
- `make test`：TEST SUCCEEDED — 75 XCTest + 7 XCUITest，0 失败。
- `make lint`：passed。
- 文档同步：overview（effects/专注钉住描述）、spec、runbook 已核对。
