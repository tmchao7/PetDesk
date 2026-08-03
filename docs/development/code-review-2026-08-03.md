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

---

# 第二轮 Review（同日追加）

焦点：UI/AppKit 层、图像/AI 管线、第一轮遗留项复核、新写链正确性。
三个并行审计，处置如下。

## 修复（第二轮）

| 修复 | 问题 |
|---|---|
| 激活策略引用计数（AppEnvironment.auxiliaryWindowCount） | 多窗口同时打开时，关掉一个窗口就把 activationPolicy 无条件降回 .accessory → Dock 图标消失、Cmd-Tab 失效、其余窗口失焦；统一 onAppear +1/onDisappear -1，归零才降级。同时消除 MenuBarView.dismissThen 的 .regular 永久泄漏窗口（0.15s 内窗口未显示即关闭时） |
| `loadSourceForEdit` 失败清 `avatarSourceImage` | 头像重导入失败时残留旧源图 → 编辑器弹旧图，可能误确认覆盖当前头像；另加 `cancelAvatarEdit()`（取消编辑释放 4MB 源图） |
| `AvatarEditorView` 平移/缩放跨手势累计 | DragGesture.translation 每手势从 0 开始、MagnificationGesture.value 从 1.0 开始 → 松手重拖/重捏会 snap 回中心/1x；用 @GestureState 记录手势起点 |
| `AvatarCropper` 方形 clamp | 非方形源图像边缘裁剪时 safeW≠safeH，非方形区域被拉伸到 1024×1024 输出 → 变形；取 min 重新居中夹紧 |
| `DayStats.todayKey` 共享 formatter 只读化 | 共享 DateFormatter 被写 calendar 属性（非线程安全）；改只读共享 + 非默认日历走临时实例 |
| `GPTImage2Provider` 响应尺寸校验 | AI 返回 <256px 的图会模糊（抠底色键阈值按 ~1024px 调参）；拒绝并走回退 |
| XCUITest 假阳性断言删除 | `app.images["moon.zzz.fill"]`/`["keyboard"]` 查询的 SF Symbol 名从不暴露为 accessibility identifier → 断言永远通过、零覆盖；删除（emoji 覆盖功能已移除） |

## 复核结论（第一轮遗留项）

- **确认误判**：精灵图行坐标"反转"（第三 agent 引 Apple 文档称 cropping 左下原点；
  项目 runbook 实测 macOS 26 SDK 为左上原点，`checkRowCellGeneration` 用每行不同
  颜色逐像素锁定映射，且自定义姿势功能实测正常）→ 不改。
- **确认误判**：`scaledEyeBand` Y 轴"应改用 frameHeight(208)"——映射目标是 192×192
  方形基准（fittedBase），用 frameWidth 正确 → 不改。
- **确认正确**：pendingWrite 串行链跨天写键安全、MainActor 诊断安全、transforms
  数组长度与 frameCount 全部匹配（逐行核对）。
- **接受（注释说明）**：终止时写链不等完成（最多丢 30s 统计，30s 批量写窗口）；
  专注钉住抹高温 smoke（设计如此，已加注释）；pendingWrite 强捕获 self（单例
  生命周期，无害）；低风险项（CGEventType 哨兵、flood 8MB 栈、字节序自洽、
  双预乘少见输入、autoreleasepool）记录不修改。

## 验证（第二轮）

- `swift run PetDeskCoreChecks`：passed。
- `make test`：TEST SUCCEEDED — 75 XCTest + 7 XCUITest，0 失败
  （XCUITest 删除 3 个假阳性断言后仍全过）。
- `make lint`：passed。
