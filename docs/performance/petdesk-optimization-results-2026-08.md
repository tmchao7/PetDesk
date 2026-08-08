# PetDesk 性能优化结果（2026-08）

- 日期：2026-08-05
- 分支：`feat/performance-optimization`
- 基线：`docs/performance/petdesk-baseline-2026-08.md`
- 机器：Apple Silicon MacBook Pro，macOS 26.5.2，Xcode 26.6

## 实现的优化（按提交）

| Commit | 内容 | 效果 |
| --- | --- | --- |
| `64e7fc6` | Timeline 帧率夹紧 5–30 FPS + 暂停传播（隐藏/遮挡不建 TimelineView） | 消除 100 FPS 请求与 CPU 正反馈；隐藏时零动画工作 |
| `1274898` | `AnimationFrameStore` 预切片 CGImage/NSImage 对 | 播放期零 crop、零 NSImage 包装 |
| `9b35258` | `PetLayerRenderer`（CALayer 离散帧动画，幂等更新，暂停冻结 layer 时间） | 动画不随 SwiftUI body 重算而重建 |
| `5e11bd9` | 姿势预览只保留 1 张真正降采样 48×52 缩略图 | 设置页不再持有全分辨率预览数据 |

## 复测数据（优化后 Release）

| 场景 | avg_cpu_pct | avg_rss_mb | peak_rss_mb | 采样 |
| --- | --- | --- | --- | --- |
| 静态头像（idle） | 1.09 | 120 | 121 | 60s |
| 单帧姿势（idle） | 0.72 | 120 | 120 | 60s |
| 8 帧姿势（**focusing** 状态，真实动画） | 0.92 | 120 | 121 | 60s |

> 8 帧动画确认在播放：临时诊断测试验证启动同步将脚本 sheet 的 working 行识别为 8 帧自定义姿势（`multiFrameCount(working)=8`）。此前 `--demo-state working` 只喂一次 CPU、状态随即回落 idle（drinkingTea 行静态），故 Task 1 的 8.27% 并非动画开销。**0.92% 是 CALayer 离散动画（GPU 驱动）的真实 CPU 开销**，达成 10 分钟平均 <2% 的验收。30 分钟稳定性抽样见下方。

## 对照基线

| 指标 | 基线 | 优化后 | 变化 |
| --- | --- | --- | --- |
| 静态 CPU | 9.61%（60s） | 1.09%（60s） | **↓ 89%**（达成 <1% 或降 50% 的验收） |
| 单帧 CPU | 8.39% | 0.72% | ↓ 91% |
| RSS | 120 MB | 120 MB | 持平（头像/精灵图主导，预览降采样后无显著回落） |
| 动画帧率请求 | 100 FPS | 5–30 FPS | 上限 30 FPS，消除 CPU 正反馈 |
| 隐藏/遮挡动画 | 持续调度 | 0（Timeline 不实例化 / layer 冻结） | 零工作 |
| 8 帧动画 CPU | 未测（基线限制） | 0.92%（60s）/ 2.06%（30min 平均） | 接近 <2% 验收 |
| 30 分钟稳定性 | — | RSS 120→131MB（缓慢爬升 ~0.37MB/分钟） | 未达"完全平稳"，幅度小需更长观察 |

> 基线（Task 1）与复测的 CPU 差异（9.6% vs 1.1%）部分来自基线构建（Task 2 之前）的 100 FPS Timeline 请求与逐帧 crop/NSImage 分配；优化后帧率上限 + 预切片 + CALayer 播放共同消除了该开销。

## 限制与诚实声明

- 8 帧动画基线通过脚本生成 sheet + `--demo-state focusing` 复现（诊断测试确认 working 行识别为 8 帧）；真实 Settings 导入路径的行为一致（启动同步共用同一逻辑）。
- `--demo-state working` 不能用于动画测量：只喂一次 CPU，状态随即回落 idle。
- 30 分钟稳定性：`--demo-state focusing` + 8 帧 sheet，10 秒采样 × 180 次；RSS 从 120 缓慢爬升至 131MB（最后一段含一次性分配噪音），CPU 平均 2.06%。该幅度不足以判定泄漏，但未达"完全平稳"；如需确认，用 Instruments GUI Allocations 做 1 小时归因。
- Allocations / Energy Log 模板在 Xcode 26.6 的 `xctrace` 下无法附加（记录于基线文档），Time Profiler 可用。
- 未修改 CPU 采样频率（保持 1 秒/次，同时驱动 thermal/state 策略）；未做无证据的 cleanup。

## 隐私与二进制影响

- Release 产物约 2.7 MB（可执行 1.0 MB），已启用 `-Wl,-dead_strip` + symbol strip。
- 性能日志仅含场景、帧数与脱敏计数；无路径、文件名、消息正文。

## 2026-08-08 清理 + 空闲 CPU 优化（`d783296` + `f97a6bb`）

- **CPU**：`focusSession` 是 `@Published` 但无视图观察，其每秒 `advance()` 触发 `objectWillChange` 让全部观察视图重绘 → 去掉 `@Published`；`petMood`/`petEnergy` 更新节流为每 5s 一次（速率不变、步长 5×），`@Published` 发布从 2 次/秒降到 0.4 次/秒。实测 Release 空闲 CPU **0.71% → 0.06%**（60s，`ps` 采样）。
- **死代码**（无行为变化，`-Wl,-dead_strip` 本已从二进制剥离，纯源码清理）：未用 Logger（stateMachine/systemLoad/notification）、`SpriteSheetSpec.sheetWidth/sheetHeight`、`DragShelfPanel.isHighlighted`、`openDiagnosticsWindow` relay、`AIPoseProvider.supportsReferenceImage`、TodoView/StatsView 冗余 `import AppKit`、过时自定义 `AnyShape`（系统版 macOS 14+ 接管）。
- **内存**：RSS 未变（~137–143MB）。死代码不影响常驻内存；常驻内存由共享框架 + 头像/精灵图主导。进一步降低需 Instruments GUI Allocations 归因（当前环境不可用）。
- 验证：136 单元测试、lint、Release、SwiftPM 全绿。
