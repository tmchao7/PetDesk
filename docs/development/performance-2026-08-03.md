# PetDesk 轻量化整改报告（2026-08-03）

目标：让 .dmg 安装的 PetDesk 在 macOS 上尽可能少占 CPU / 内存，删除冗余代码。
方法：先联网检索 macOS / SwiftUI 应用轻量化最佳实践，再审计本项目热点，逐项整改，
最后在同一台机器、同一 Debug 构建配置下对比整改前后占用。

## 检索来源（方案参考）

- [Dimillian/Skills · swiftui-performance-audit](https://github.com/Dimillian/Skills/blob/main/swiftui-performance-audit/SKILL.md)
  —— 无效化风暴、body 内重活、DateFormatter 缓存、图像降采样等 SwiftUI 性能清单。
- [Shape-Machine/tusk-macos#57 · TabView 生命周期](https://github.com/Shape-Machine/tusk-macos/issues/57)
  —— 视图常驻/重建对内存的影响。
- [Swift Forums · Combine collect(byTime) 常驻定时器](https://forums.swift.org/t/combines-collect-bytime-schedules-a-repeating-timer/57456)
  —— Combine 定时器是隐藏 CPU 陷阱；本项目使用 `Task.sleep` 结构化并发，未踩坑。
- [Stack Overflow · SwiftUI + Combine Timer 泄漏](https://stackoverflow.com/questions/63321923/how-can-i-avoid-this-swiftui-combine-timer-publisher-reference-cycle-memory)
  —— `[weak self]`、AnyCancellable 存储与清理规则；本项目已符合。
- [iOS and macOS Performance Tuning（Marcel Weiher）](https://www.worldofbooks.com/products/ios-and-macos-performance-tuning-book-marcel-weiher-9780321842848/)
  —— 先测量再优化、修资源泄漏、避免常见 Swift/Objective-C 性能陷阱。
- [Apple · NSPanel/nonactivatingPanel 文档](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
  —— 悬浮窗本就是低开销原语；透明窗口 GPU 合成属特性固有成本，不越界优化。

## 审计发现（改动前）

**已达标（无需改动）**：无 Combine `Timer.publish`/`autoconnect`/`CADisplayLink`；
所有 Task 用 `[weak self]` 且可取消；无 force-unwrap；Combine 订阅无泄漏；
图片导入已降采样（1024px）。常驻内存大头是精灵图 1536×1664 ≈ 10 MB（特性固有）。

**热点**：
1. `@Published snapshot` 每秒发布（状态机每秒 tick），悬浮窗 `PetView` /
   `PetBubbleView` / `PetWindowController` 整树每秒重算——而 CPU 读数
   （`averageCPU`）每秒都在变，是发布风暴主因；悬浮窗视图并不读它。
2. `AnimatedAvatarView` 每次 body 求值重新裁剪帧 + 包装 NSImage。
3. `DayStats.todayKey()` 每秒创建 `DateFormatter`（创建需加载 locale 数据）。
4. `StatsView` 每次 body 求值创建约 21 个 `DateFormatter`。
5. `PetView` 保留 phase 动画数学（sin 浮动/旋转），但静态模式下 phase 恒为 0，
   全部恒等变换，属死代码。
6. `AnyShape` 在 4 个文件重复定义。
7. `PetWindowController` selector 式观察者无 deinit 移除（理论崩溃风险）。

## 整改内容

| # | 文件 | 改动 | 收益 |
|---|---|---|---|
| 1 | `PetDomain/PetState.swift`、`App/AppEnvironment.swift` | 新增 `PetSnapshot.displayEquals`（显示字段：baseState/transient/effects/bubble）；`handle()` 仅在显示字段变化时发布快照 | 消除每秒整树重绘；CPU 度量只进诊断窗口 |
| 2 | `Avatar/AnimatedAvatarView.swift` | 按（精灵图, 行, 帧索引）缓存裁剪结果 NSImage | 状态切换时不再重复裁剪/包装 |
| 3 | `UsageStats/DayStats.swift`、`StatsView.swift` | `DateFormatter` 全部改共享实例 | 每秒一次 + 每次渲染 21 次的创建开销归零 |
| 4 | `PetRender/PetView.swift` | 删除 phase 恒 0 的 sin 动画数学与 3 个死函数，仅保留受惊 1.08 放大 | 移除冗余代码与每次求值的 switch/三角函数 |
| 5 | 新建 `Shared/AnyShape.swift` | 4 份重复 `AnyShape` 收口共享 | 消除重复类型定义 |
| 6 | `PetWindow/PetWindowController.swift` | `deinit` 移除 selector 观察者 | 消除悬垂通知风险 |
| 7 | 新建 `scripts/measure-petdesk.sh` | 60/90s 采样 CPU%/RSS 测量脚本 | 可复现的前后对比 |

新增测试：`Checks/main.swift` 的 `checkSnapshotDisplayEquality()`（先红后绿）；
`PetDeskTests/AppEnvironmentTests.swift` 3 个用例适配新契约
（averageCPU 不再驱动发布，改用显示状态变化验证事件处理）。

## 测量结果（Debug 构建，同机，60–90s 空闲采样）

| 指标 | 整改前（2 次） | 整改后（2 次） | 变化 |
|---|---|---|---|
| CPU（平均） | 0.41% / 0.30%（≈0.36%） | 0.29% / 0.23%（≈0.26%） | **↓ 约 28% 相对，约 0.10pp 绝对** |
| RSS（平均） | 109 MB | 109 MB | 不变 |
| RSS（峰值） | 109 MB | 109 MB | 不变 |

测量方法：`scripts/measure-petdesk.sh <app> [秒数] [预热秒]`——启动后预热 15s，
逐秒 `ps -o %cpu=,rss=` 采样，输出平均 CPU / 平均 RSS / 峰值 RSS。
注意：XCUITest 会占用同 bundle ID 的 app 实例，测量期间不要并行跑 `make test`。

## 结论与取舍

- 空闲 CPU 由 ~0.36% 降至 ~0.26%（相对 -28%）。绝对幅度小，因为基线本来就很低；
  真正的收益在交互/状态切换时——视图不再被每秒 tick 无效化，发热与电量消耗更稳。
- RSS 不变：常驻内存大头是精灵图（10 MB）与头像（4 MB），均特性固有；
  两处冗余解码头像（`avatarImage` + `avatarBaseCGImage` ≈ 4 MB）经评估因需将
  多处方法异步化、回归风险大于 3.7% 收益而跳过。
- 三个 1 秒循环（tick / CPU / idle）保持独立：合并会破坏
  `PetSignalSource` 抽象，且每次唤醒成本为微秒级，无实际收益。
- 透明悬浮窗 GPU 合成成本属特性固有，未越界优化。
- 已知语义变化：`snapshot.averageCPU` 只在显示字段变化时随快照发布
  （诊断窗口头部 CPU 读数允许滞后约 1 秒；事件列表不受影响）。
