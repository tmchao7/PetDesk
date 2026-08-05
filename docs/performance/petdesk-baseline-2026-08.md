# PetDesk Release 性能基线（2026-08）

- 日期：2026-08-05
- 分支：`feat/performance-optimization`（Task 2 之前，`64e7fc6` 前一个提交）
- 构建：`xcodebuild -configuration Release -derivedDataPath /tmp/PetDeskDerived CODE_SIGNING_ALLOWED=NO`
- 产物：`/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app`（2.7 MB，可执行 1.0 MB）
- 机器：Apple Silicon MacBook Pro，macOS 26.5.2，Xcode 26.6
- 采样：`scripts/measure-petdesk.sh <app> 60 15`（60 秒 × 1 秒采样，15 秒启动沉降）
- 头像：程序生成 200×200 测试头像（无自定义姿势时的默认渲染）

## 结果

| 场景 | avg_cpu_pct | avg_rss_mb | peak_rss_mb | 说明 |
| --- | --- | --- | --- | --- |
| 静态头像（idle） | 9.61 | 120 | 120 | 无自定义姿势，working 行 6 帧程序化微变换，静态显示 |
| 单帧姿势（idle） | 8.39 | 120 | 120 | working 行 1 帧自定义姿势，静态显示 |
| 8 帧姿势（working 状态） | 8.27 | 120 | 120 | 见下方限制说明 |

## 限制与诚实声明

- **8 帧动画场景未可靠复现**：通过临时脚本写入的 `spritesheet.png`（working 行 8 个不同裁切帧）未被 AppEnvironment 的启动恢复逻辑识别为自定义姿势（对比阈值/处理链未命中），实际仍以静态渲染运行——因此 `8.27%` 不能代表真实 8 帧动画热点的基线。
- 真实 8 帧动画基线需要**通过 Settings → 头像 → 专注姿势 多选导入 8 帧**后测量；该测量在 Task 7 复测阶段由拥有者执行或经真实导入路径补齐。
- Allocations / Energy Log 模板：Xcode 26.6 下 `xctrace` 无法附加（codex 已记录同样失败），Time Profiler 可用。
- Debug 对照（codex 记录）：约 131.7 MB RSS / 9.3% CPU——与本次 Release 静态基线（120 MB / 9.6%）趋势一致。

## 采样命令（可复现）

```bash
make generate
xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Release \
  -derivedDataPath /tmp/PetDeskDerived build CODE_SIGNING_ALLOWED=NO
scripts/measure-petdesk.sh "/tmp/PetDeskDerived/Build/Products/Release/PetDesk.app" 60 15
```

## 与验收目标对比

| 指标 | 基线（本次） | v1 验收 | 差距 |
| --- | --- | --- | --- |
| 空闲静态 CPU | 9.6%（Release，60s） | <1% 或相对下降 50% | 需要优化 |
| 8 帧姿势 CPU | 未测（见限制） | 10 分钟平均 <2% | 待测 |
| RSS | 120 MB | 接近 100 MB | 需降 20 MB |
| 动画帧率 | 100 FPS 请求（Task 2 前） | 5~30 FPS 上限 | Task 2 已实现 |
