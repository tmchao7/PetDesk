# Current Agent Handoff

- Status: ready
- Active owner: unassigned
- Updated: 2026-09-05T15:50:00+0800
- Branch: `main`
- Latest release commit: `39c0e8b`（chore(release): bump version to 2.1.1）
- Release tag: `v2.1.1`
- Latest session: [codex release-2-1-1](sessions/2026-09-05-1549-codex-release-2-1-1.md)
- Previous implementation session: [codex pose-memory-lifecycle](sessions/2026-09-05-1526-codex-pose-memory-lifecycle.md)
- Previous implementation session: [codex lightweight-optimization](sessions/2026-09-05-1505-codex-lightweight-optimization.md)
- Previous audit session: [codex app-audit](sessions/2026-09-05-1443-codex-app-audit.md)
- Previous implementation session: [codex reminder-drag-fix](sessions/2026-09-05-1347-codex-reminder-drag-fix.md)

## Active Objective

v2.1.1 patch release 已完成并发布：包含前两批轻量化整改、专注/拖动体验修复、版本号更新、Release DMG 和 GitHub Release。下一步是 owner 手动安装验收与真实八帧姿势 Release 测量；窗口尺寸、动态阴影和 Drag Shelf 隐私契约仍未改动。

## Repository Snapshot

- `main` / `origin/main` 基线未修改；修复分支为 `fix/reminder-and-drag-smoothness`。
- 原始体验修复提交：`dc1bca5`；前一轮性能提交：`22bb5eb`；姿势内存提交：`6393ca1`；版本提交：`39c0e8b`。
- 专注设置现在同时控制手动专注会话总时长和连续专注提醒；运行中修改会重置两者累计。
- 拖动期间抑制 UserDefaults 写盘和 `petWindowFrame` 发布，鼠标释放时保存最终位置。
- 工作区原有未跟踪 `.mimosa/`、`.zcode/`、`picture.png` 保留，未读取或修改。
- 生成的 `PetDesk.xcodeproj` 未编辑或提交。
- `project.yml` 和 README 版本已更新为 `2.1.1`。
- `v2.1.1` annotated tag 和 GitHub Release 已推送，DMG 资产已上传。
- CALayer 多帧路径现在使用 CGImage-only 缓存；SwiftUI fallback 才按需创建 NSImage 包装。
- 手动钉住状态仍锁定外观，但继续消费 CPU 指标并更新动画速度。
- `petScale`、动画速度和 Todo 持久化采用 300ms debounce，应用停止时 flush。
- AppEnvironment 只保留每个自定义姿势行的帧数；完整姿势帧仅在重组调用期间临时存在，清除行时从 spritesheet 临时恢复其他行。
- 本次只读审计确认：CALayer 路径仍额外创建 NSImage 帧包装、AppEnvironment 保留姿势帧与完整精灵图两份像素、手动锁定状态会冻结 CPU/动画速度信号；拖拽托盘还存在持久化文件路径与隐私规则冲突。

## Latest Verification

- 前一轮定向回归测试：4/4 通过。
- 本轮姿势生命周期定向测试：1/1 通过。
- 本轮完整单元测试：158/158 通过。
- 完整 UI 测试：7/7 通过。
- `make lint`：通过。
- `swift run PetDeskCoreChecks`：通过。
- `make verify`：通过，包含 handoff checks、Debug/Release 构建、158 个单元测试和 7 个 UI 测试。
- 本轮 Release 默认静态启动采样（60 秒）：`avg_cpu_pct=.09`、`avg_rss_mb=122`、`peak_rss_mb=123`；尚未代表真实八帧导入姿势场景。
- v2.1.1 DMG：`dist/PetDesk-2.1.1.dmg`，本地约 2.4 MB；GitHub Release 资产已确认上传。
- 发布前和推送钩子验证均通过，包含 158 个单元测试和 7 个 UI 测试。

## Confirmed Fixes

1. `FocusSession` 不再在生产默认路径固定使用 25 分钟，而是由 Settings 的 `focusDurationMinutes` 创建和更新。
2. `focusDurationMinutes` 变更时，活动专注会话和连续提醒累计都重新开始，避免旧累计导致提前提醒。
3. 拖动窗口时仍采用全局屏幕坐标计算位移；新增持久化门控，拖动中不写盘、不发布窗口 frame，释放鼠标后一次性同步。
4. 新增回归测试和产品/架构文档说明。

## Blockers

- 当前无代码验证阻塞；XCUITest runner 在 2026 年 9 月 5 日发布验证中已成功运行。
- 真实八帧姿势 Release 测量、长时间 RSS 稳定性、Instruments 归因和签名/公证仍待后续工作。

## Audit Follow-up

1. 已确认并实现：手动专注/摸鱼/放松时动画速度继续随 CPU 更新，外观状态仍保持钉住。
2. Drag Shelf 仍待产品确认；当前实现持久化完整文件路径，与隐私规则冲突。
3. 后续优化优先处理姿势帧按需加载，并用 Release Instruments 验证动态阴影、唤醒次数和长时 RSS。

## Next Actions

1. Owner 手动验证 Slider 快速调整后的恢复、Todo 快速编辑后的最终保存，以及手动专注动画速度响应 CPU。
2. 通过 Settings 导入真实 8 帧专注姿势，重复 Release CPU/RSS 测量。
3. 决定 Drag Shelf 的隐私/持久化契约。
4. 若数据仍显示有收益，再处理姿势帧按需加载、动态阴影和 wakeup profiling。
