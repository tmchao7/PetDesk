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
| 8 帧姿势（working 状态） | 0.83 | 120 | 121 | 60s |

> 600 秒复测因测量脚本与并行验证的 `pkill` 冲突而中断；采用同机同脚本 60 秒数据。8 帧场景沿用脚本生成的 sheet（启动同步未识别为自定义姿势，实际为静态渲染路径）——真实 8 帧动画基线需经 Settings 导入路径补测（见限制）。

## 对照基线

| 指标 | 基线 | 优化后 | 变化 |
| --- | --- | --- | --- |
| 静态 CPU | 9.61%（60s） | 1.09%（60s） | **↓ 89%**（达成 <1% 或降 50% 的验收） |
| 单帧 CPU | 8.39% | 0.72% | ↓ 91% |
| RSS | 120 MB | 120 MB | 持平（头像/精灵图主导，预览降采样后无显著回落） |
| 动画帧率请求 | 100 FPS | 5–30 FPS | 上限 30 FPS，消除 CPU 正反馈 |
| 隐藏/遮挡动画 | 持续调度 | 0（Timeline 不实例化 / layer 冻结） | 零工作 |

> 基线（Task 1）与复测的 CPU 差异（9.6% vs 1.1%）部分来自基线构建（Task 2 之前）的 100 FPS Timeline 请求与逐帧 crop/NSImage 分配；优化后帧率上限 + 预切片 + CALayer 播放共同消除了该开销。

## 限制与诚实声明

- 8 帧真实动画基线依赖 Settings 导入流程（脚本生成的 sheet 不会被启动同步识别为自定义姿势）；若无法自动复现，标注为待拥有者手动测量。
- Allocations / Energy Log 模板在 Xcode 26.6 的 `xctrace` 下无法附加（记录于基线文档），Time Profiler 可用。
- 未修改 CPU 采样频率（保持 1 秒/次，同时驱动 thermal/state 策略）；未做无证据的 cleanup。

## 隐私与二进制影响

- Release 产物约 2.7 MB（可执行 1.0 MB），已启用 `-Wl,-dead_strip` + symbol strip。
- 性能日志仅含场景、帧数与脱敏计数；无路径、文件名、消息正文。
