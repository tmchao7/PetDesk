# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-29T17:10:59+0800
- Agent: zcode
- Role: 调研 AI 帧图漂移问题并产出治理规划（研究/规划会话，无代码改动）
- Objective: pose frame consistency plan
- Status: ready
- Branch: feat/pose-frame-consistency
- Starting commit: 591dd72
- Ending commit: 本记录所在 docs 提交（提交后补充哈希）

## Context Read

- `docs/agent-handoff/CURRENT.md` + `2026-08-09-2127-claudecode-rescue-expansion-escape.md`
- `docs/product/petdesk-v1-spec.md`、`docs/architecture/overview.md`、`docs/architecture/state-machine.md`
- `docs/development/git-workflow.md`、`docs/prompts/doubao-sprite-prompt.md`
- `PetDesk/Features/Avatar/PoseFrameSetProcessor.swift`、`PoseCellProcessor.swift`、`PoseSheetSlicer.swift`
- `PetDesk/App/AppEnvironment.swift`（importPose/multiFrameCount）、`PetDesk/Features/Settings/SettingsView.swift`（漂移告警）、`PetDesk/Features/PetRender/PetView.swift`（多帧播放按行）
- Git 状态：分支 `feat/pose-frame-consistency` 上存在**未提交改动**（PoseFrameSetProcessor/PoseSheetSlicer 及测试、Checks/AppEnvironment/SettingsView 修改）——本次会话未触碰这些 WIP。

## Work Performed

纯研究/规划会话，无生产代码改动。产出：

1. **现状梳理**：多帧导入已有跨帧归一化（统一背景/统一缩放/质心+地面锚点 ±18px）与漂移诊断（面积比 ≤1.26、质心 ≤18px）；`PoseSheetSlicer` 支持长条带切帧；任意行 >1 帧即循环播放；Settings 仅有首帧缩略图 + ⚠️。
2. **外部调研**（联网，来源见规划文档引用）：
   - OpenAI 官方 `openai/plugins` game-studio **sprite-pipeline** skill：判词"逐帧生成必然漂移"，官方路径 = 种子帧 + 单次整条带生成 + 归一化（固定尺寸/单一缩放/bottom-center 锚点）+ 可选 lockback + prompt invariants 清单。
   - Codex **hatch-pet**：全自动管线（image-gen 基础图 → 子代理变化帧 → pet.json + spritesheet），用户从不逐帧手搓；动画表由 app 持有。
   - GitHub **aldegad/sprite-gen**：soft-alpha unmix 抠底、多 take 候选池挑帧重建循环、非破坏性变换 sidecar、实时循环预览、Breathe 单帧微动画。
   - 社区主流：**图生视频 → 抽帧 → 去背对齐**（时间一致性最好；即梦/豆包/可灵可用）。
3. **方案决策**：否决"让用户逐帧手搓三组"为主路径；采纳 B（种子帧整条带引导）+ D（色彩归一化 + 循环预览）为 P1，C（视频导入抽帧，AVFoundation）为 P2，帧管理/多 take/单帧微动画为 P3。
4. **产出规划文档**：`docs/superpowers/plans/2026-08-29-pose-frame-consistency.md`（含分期任务、guardrails、验收标准、File Map）。

## Decisions

- 主路径改为"种子帧 + 一次整条带生成 / 图生视频抽帧"，与 OpenAI 官方 sprite-pipeline 判词一致（逐帧独立生成是一致性最差路径，仅作兜底导入路径保留）。
- P1 优先做**跨帧主体色彩归一化**（现管线只统一了背景色，主体色调漂移未治理）与 **Settings 循环预览**（验收闭环），均为低成本高收益。
- 视频抽帧用 AVFoundation（系统框架），符合零第三方依赖规则；完全本地解码，不持久化视频文件。
- 分支上既有未提交 WIP（归一化实现）归属待确认，本计划实施前须先与 owner 确认其提交/归属，规划文档已列入 guardrails。

## Verification

- 本会话无代码改动，未运行 `make test`/`make verify`（不适用）；`make handoff-check` 通过后随 docs 提交。
- 所有调研结论来自联网检索与源码阅读，未写入任何未经验证的行为断言。

## Review and Debug Findings

- `PetView` 按 `multiFrameCount(for:)` 对任意行播放多帧（"6 帧动画支持已确认"与代码一致）。
- 现有 `PoseFrameDiagnostics` 阈值注释声称参考 Codex hatch-pet 验收标准，本次未找到官方公开的该数值来源，属先前会话结论，保持原样未改动。
- 提示词文档"导入 PetDesk"一节与实际行为已基本一致（长图自动切帧已实现），P1 Task 1.1 只需小幅修正表述。

## Open Issues and Risks

- `feat/pose-frame-consistency` 分支存在大量未提交实现（PoseFrameSetProcessor/PoseSheetSlicer/测试/Checks），CURRENT.md 尚未记录该 WIP 的会话记录——需要 owner 或实施会话补记并提交。
- 色彩归一化的保护阈值（防止真实配色差异被"平均掉"）需真实帧图调参验证。
- 视频抽帧对 HEVC/动态范围视频的色彩空间转换需在 P2 实现时验证。

## Next Actions

1. Owner：确认 `feat/pose-frame-consistency` 未提交 WIP 的归属并提交（verify 全绿后），或并入本计划 Phase 0。
2. 实施 P1：Task 1.1 提示词文档重写 → Task 1.2 色彩归一化（先失败测试）→ Task 1.3 循环预览 → Task 1.4 告警细化；按规划文档逐任务推进。
3. P2 视频导入抽帧排期待 owner 确认。

## Git State

- Branch: `feat/pose-frame-consistency`（自 `fix/pose-cell-keying-leak` 演进，HEAD `591dd72`）。
- Working tree：大量未提交改动（见 Context Read）；`picture.png`、`.mimosa/`、`.zcode/` 未跟踪（禁止提交）。
- 本会话新增：`docs/superpowers/plans/2026-08-29-pose-frame-consistency.md`、本记录、CURRENT.md 更新。
