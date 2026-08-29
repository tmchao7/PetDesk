# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-29T17:10:59+0800
- Agent: zcode
- Role: 调研 AI 帧图漂移问题并产出治理规划（研究/规划会话，无代码改动）
- Objective: pose frame consistency plan
- Status: ready
- Branch: feat/pose-frame-consistency
- Starting commit: 591dd72
- Ending commit: `620e3ed`（feat 实现提交）+ docs 提交（本记录更新）

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

- **2026-08-29 17:44（zcode，本会话第二轮）**：分支上的未提交归一化 WIP 经 owner 要求用自动化门禁验证。`make verify` 首跑失败：① `AppEnvironment.swift:516` 闭包内引用 `customPoseCells` 缺显式 `self.`（Swift 6 编译错误）；② `PoseSheetSlicerTests.testSliceFallsBackWhenACellIsEmpty` 失败（实现 bug：`cellLooksLikeFrame` 只按 alpha 判主体，不透明绿幕背景的空格被误判有主体，未回退单帧）；③ `PoseFrameSetProcessorTests.testProcessUnifiesBackgroundEstimationAcrossFrames` 失败（测试探针 `(96,1)` 落在撑满单元全高的主体内，属测试 bug）。修复：显式 `self.`；`cellLooksLikeFrame` 内部主体判定改为"透明或与四边中位数背景色明显不同"（距离阈值 0.18 复用切线边语义）；探针移到主体水平范围外 `(170,1)`；并 `swift format --in-place` 清掉 format 警告。修复后 `make verify` **全绿**：149 单元测试 + 7 UI 测试 0 失败、Debug/Release 构建、swift format lint 无警告、`PetDeskCoreChecks` all checks passed、禁止构造扫描通过。WIP 连同修复以 `620e3ed`（feat(avatar): normalize multi-frame pose imports across frames）入库。
- 本会话第一轮为纯研究/规划，无代码改动。调研结论来自联网检索与源码阅读。
- **2026-08-29 18:58（zcode，推送轮）**：owner 指示合并 main 并推送。`git merge --no-ff` → main `96ed77c`，docs 提交 `220d5a9`。`git push origin main` 前两次失败：pre-push `make verify` 均挂在 `PetDeskSmokeTests.testFakeNotificationStillLaunchesWithoutAccessibilityPermission`（"Failed to terminate io.github.tmchao7.PetDesk:98889"）。根因排查：PID 98889 是 **17:55 从 Xcode 调试器启动的 Debug 构建 PetDesk**（父进程为 Xcode 派生的 debugserver 98902，主线程空闲非挂起），UI 测试启动时终止同 bundle ID 的该实例失败——即"UI 测试 runner 间歇性崩溃"的又一具体诱因：**Xcode 调试运行会话挂着时会卡死所有 UI 测试**。终止 debugserver + 应用实例后第三次 `git push` 成功：pre-push verify 全绿（同 149+7 规模），`a36ef48..220d5a9 main -> main`。未使用 `--no-verify` 绕过钩子。

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

- Branch: `feat/pose-frame-consistency`（未推送）：`591dd72` → `b10986e`（docs plan）→ `620e3ed`（feat 归一化实现 + 本轮修复）→ docs 提交（本记录更新）。
- 原未提交 WIP（归一化实现）已随 `620e3ed` 入库；working tree 仅剩未跟踪的 `picture.png`、`.mimosa/`、`.zcode/`（禁止提交）。
