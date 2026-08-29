# Pose Frame Consistency Plan（AI 帧图漂移治理）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解决用户用 AI 一次性生成整组动画帧导入后，帧间漂移（错位、忽大忽小、颜色异常、色调漂移）导致动画不连贯的问题。确立"生成端引导 + 应用端归一化 + 预览验收"三层方案，并按 OpenAI 官方 sprite-pipeline 的经验把用户生成路径从"逐帧手搓"引导到"种子帧整条带生成 / 图生视频抽帧"。

**Architecture:** 生成端只改提示词文档（不改代码契约）；应用端增强复用 `PoseFrameSetProcessor` 单趟管线（统一背景 → 统一抠底 → 统一缩放 → 统一锚点 → 单元渲染），新增"跨帧主体色彩归一化"作为抠底后的一个阶段；预览验收复用 `AnimationFrameStore` 预切片帧在 Settings 内低频播放。所有行为仍经由现有导入入口 `AppEnvironment.importPose(row:from:)`，不新增状态选择逻辑。

**Tech Stack:** Swift 6 strict concurrency, CoreGraphics, AVFoundation（视频抽帧，系统框架、零第三方依赖）, SwiftUI, XCTest。

---

## Background and Research（2026-08-29 调研结论）

### 现状（已落地）

- **应用端归一化**：`PoseFrameSetProcessor` 已做统一背景估计（整组帧边缘中位数的逐通道中位数）、统一缩放（最大包围盒决定）、统一锚点（水平=强主体质心中位数、垂直=包围盒底边地面中位数，±18px 矫正）、漂移诊断（面积比 ≤1.26、质心偏移 ≤18 单元像素，参考 OpenAI Codex hatch-pet 验收标准）。
- **长条带切帧**：`PoseSheetSlicer.sliceStrip` 支持单文件横向帧条带自动切帧。
- **用户引导**：`docs/prompts/doubao-sprite-prompt.md` 提供"照片 → 卡通角色 → 3 状态 → 每组 8 帧长图"三步模板（绿幕背景）。
- **告警**：Settings 在漂移超阈值时显示 ⚠️（提示"用首帧作参考图重新生成"）。
- **动画播放**：任意行导入 >1 帧即循环播放（`PetView` 按 `multiFrameCount(for:)`），CPU 调速 5–30 FPS。

### 遗留问题

1. **主体颜色漂移未治理**：只统一了"背景色"，主体（服装/皮肤/道具）的跨帧色调漂移直接进 cell，播放时呈现"颜色异常"。
2. **无验收闭环**：Settings 只显示 48×52 首帧缩略图，用户导入后看不到动画是否连贯，只能切到桌面看宠物。
3. **逐帧独立生成路径漂移最大**：多选导入 6-8 张独立 AI 图时，每帧独立生成、独立配色，是漂移最严重的路径，但提示词文档未区分这条路径的风险。
4. **告警定位粗**：只有首个超阈值帧序号，用户不知道具体哪几帧坏、坏在哪个维度。

### 外部调研

1. **OpenAI 官方 `openai/plugins` → game-studio → sprite-pipeline skill**（与本问题最直接相关）：
   - 明确判词："frame-by-frame generation drifts too easily"——**逐帧生成必然漂移**，官方方案是**一张已确认的种子帧 + 单次编辑请求生成整条 strip**；
   - 归一化脚本做三件事：固定帧尺寸、**全 strip 共享单一缩放**、**单一锚点（bottom-center）**——与 PetDesk 现有归一化思路一致，可互为印证；
   - 可选 lockback：帧 1 锁回种子帧，保证循环首尾衔接；
   - prompt invariants 清单：同角色、同朝向、同色系（palette family）、同轮廓族、五官一致、服装比例一致、透明背景、精确帧数。
2. **Codex hatch-pet**：全自动管线（`$image-gen` 生成基础图 → 子代理生成变化帧 → 打包 `pet.json` + spritesheet），**用户从不逐帧手搓**；动画表与事件映射由 app 持有（自定义宠物只能提供元数据和精灵图）。启示：一致性靠"管线 + 归一化"，不靠用户技艺。
3. **aldegad/sprite-gen**（GitHub）：soft-alpha unmix 抠底保细线、连通组件提帧、**多 take 候选池挑最佳帧重建循环**、非破坏性变换存 sidecar、实时循环预览 + 逐帧步进、Breathe（单帧 → 确定性解剖感知 squash & stretch 生成 idle，头部逐位一致）。
4. **社区主流工作流（图生视频 → 抽帧）**：参考图 → 图生视频 → 按需抽帧 → 去背/对齐/去重 → 组装。视频模型的时间一致性远好于多次独立图片生成，是当前社区公认的强一致性路径；国内用户可用即梦/豆包/可灵的图生视频。现有工具：ComfyUI workflows、Scenario、Sorceress Auto-Sprite v2（上传视频抽帧对齐）、GameLab 等。

## 方案对比与决策

| 方案 | 做法 | 一致性 | 成本 | 决策 |
| --- | --- | --- | --- | --- |
| A. 用户逐帧手搓三组 | 多选导入 6-8 张独立 AI 图 | 差（漂移最大） | 0 | **否决为主路径**；保留为兜底导入路径 |
| B. 种子帧 + 一次整条带生成 | 按官方 sprite-pipeline 重写提示词文档 | 中-良 | 仅文档 | **P1 采纳** |
| C. 图生视频 → 导入抽帧 | app 内视频抽帧进现有管线 | 优 | 新功能（AVFoundation） | **P2 采纳** |
| D. 应用端色彩归一化 + 循环预览 | 管线增强 + Settings 预览 | 治颜色漂移 + 补验收 | 代码增强 | **P1 采纳** |

**核心结论**：不要让用户"手动让 AI 生成三组动画帧"（逐帧路径是漂移根源）。正确路径是 B+D 先行（零/低成本），C 作为一致性上限方案跟进。

## Scope and Guardrails

- 零第三方运行时依赖；视频抽帧只用 AVFoundation。
- 不改变 `PetStateMachine` 状态语义、CPU 调速、抠底/羽化既有契约；色彩归一化只作用于强主体像素，不触碰背景与透明度。
- 不读取、不持久化导入文件名；视频抽帧完全本地处理，无网络。
- 不直接编辑生成的 `PetDesk.xcodeproj`；新 Swift 文件由 `project.yml` source glob 自动纳入。
- 每个行为改动先写失败测试（XCTest 或 `PetDeskCoreChecks`），确认失败后再实现；每阶段独立 Conventional Commit。
- `picture.png`、`.mimosa/`、`.zcode/` 为未跟踪用户/本地文件，禁止提交。
- 分支 `feat/pose-frame-consistency` 上已有未提交的归一化实现（PoseFrameSetProcessor/PoseSheetSlicer 及测试）——实施前先与 owner 确认该 WIP 的提交/归属，不得混入本计划的提交。

## Phase 1（P1）：生成端引导 + 色彩归一化 + 循环预览

### Task 1.1 重写提示词文档（对齐官方 sprite-pipeline）

- [ ] `docs/prompts/doubao-sprite-prompt.md`：
  - 主路径改为"种子帧 + 一次整条带生成"：第 2 步产出的状态图作为参考图附给第 3 步，并写明"只改动作部位，角色其余部分保持不变"；
  - 新增 prompt invariants 清单（同角色/同朝向/同色系/同轮廓/五官与服装比例一致/绿幕背景/精确帧数/循环闭合"第 8 帧接回第 1 帧"）;
  - 新增"推荐替代路径：图生视频抽帧"一节（即梦/豆包/可灵，5 秒视频 → 每状态一段），标注 P2 支持视频直接导入、当前需自行截帧；
  - 明确"逐帧独立生成（一次一张）是一致性最差的路径"，若必须如此，每帧都要附首帧参考图并强调 invariants；
  - 修正导入表述与实际行为一致（长图自动切帧、1~8 帧任意行均可动画）。
- [ ] 验收：文档审读通过；无代码改动。

### Task 1.2 跨帧主体色彩归一化（PoseFrameSetProcessor 增强）

- [ ] 失败测试：构造同形状不同色调的帧序列（如整体色温偏移），断言归一化后逐帧主体平均 RGB 距离低于阈值（现管线该距离即为漂移量）。
- [ ] 实现：以首帧（或全帧中位数）为参考，对每帧**强主体像素**做统计色彩迁移（RGB mean/σ 匹配，或按亮度分桶的中位数映射，择一实现并测试）；背景与 alpha 不参与。归一化发生在统一抠底之后、统一缩放之前，复用 `KeyedPoseFrame` 位图。
- [ ] 色彩迁移幅度保护：mean 偏移超过保护阈值（如 ±48/255）的帧跳过归一化并计入诊断（防止把真实配色差异"平均掉"）。
- [ ] 验收：`make test` 全绿；用 18 张真实用户帧图（专注/摸鱼/休息 × 6）实测归一化前后帧间主体色调距离对比，数据记入 handoff。

### Task 1.3 Settings 循环预览（验收闭环）

- [ ] poseRow 缩略图可点击，弹出预览面板：按实际播放语义循环播放该行全部帧（复用 `AnimationFrameStore` 预切片或 `customPoseCells` 原帧），帧率用当前 CPU 调速公式（5–30 FPS），支持暂停。
- [ ] 预览为轻量 SwiftUI `TimelineView` 实现（仅设置窗口可见时存在），不引入 `PetLayerRenderer` 的窗口层依赖；跟随"遮挡暂停"语义由窗口可见性天然保证。
- [ ] 失败测试：`AppEnvironmentTests` 补预览数据源（帧数、顺序、空行回退）断言；UI 手测记入 handoff。
- [ ] 验收：`make test` 全绿 + 手测播放与桌面宠物观感一致。

### Task 1.4 漂移告警细化

- [ ] `PoseFrameDiagnostics` 增加逐帧标记（哪些帧面积比/质心/色彩越界）；Settings ⚠️ 悬停文案列出具体帧号与维度，建议文案按维度区分（"用首帧为参考重新生成第 N 帧" / "该组帧色调差异已自动校正"）。
- [ ] 验收：单测覆盖文案分支；`make verify` 全绿。

## Phase 2（P2）：视频/GIF 导入抽帧

- [ ] `importPose` 文件导入通道增加 `.movie`/`.gif`；`PoseVideoFrameExtractor`（新文件，AVFoundation）按时长均分采样 1–8 帧输出 CGImage 数组，进入 `PoseFrameSetProcessor` 既有管线。
- [ ] 采样数默认与时长匹配（如 5s 视频 → 6 帧），提供固定帧数预设（4/6/8）；不做 UI 时间轴编辑（留 P3）。
- [ ] 隐私与规则：完全本地解码；不持久化视频文件本身（仅抽取的帧进 spritesheet）；AVFoundation 调用收在 Avatar feature adapter 内，Settings 不直接触碰。
- [ ] 失败测试：合成短视频（或注入帧序列的 extractor 协议桩）验证采样帧数/顺序；`make verify` 全绿。

## Phase 3（P3，可选，按用户反馈排期）

- [ ] 帧管理：预览面板内删除坏帧/调整顺序（重新组装 spritesheet 并持久化帧序；对应 handoff 已记录的"帧数恢复"契约需同步调整）。
- [ ] 多 take 追加导入：同一状态多次导入追加到候选池，用户挑选重建循环（sprite-gen 模式）。
- [ ] 单帧微动画（Breathe 式）：摸鱼/休息仅单帧时叠加确定性 1–3% 呼吸缩放；属渲染层增强，不改变状态机；实施前补一条架构文档说明。

## Acceptance

- `make test`、`make lint`、`make verify` 全绿（每阶段提交点）。
- 真实帧图回归：18 张用户帧图处理后无全白 cell、无背景残留（既有契约不回退）。
- 色彩归一化有效：帧间主体平均 RGB 距离相对归一化前显著下降（同图前后对比，数值进 handoff）。
- 预览可用：Settings 内可直接看到连贯动画，漂移帧可被识别并定位。

## File Map

| 文件 | 责任 |
| --- | --- |
| `docs/prompts/doubao-sprite-prompt.md` | 生成端引导（种子帧整条带 / 视频路径 / invariants） |
| `PetDesk/Features/Avatar/PoseFrameSetProcessor.swift` | 跨帧归一化管线（新增色彩归一化阶段与逐帧诊断） |
| `PetDesk/Features/Avatar/PoseVideoFrameExtractor.swift`（P2 新增） | AVFoundation 视频抽帧 adapter |
| `PetDesk/Features/Settings/SettingsView.swift` | 循环预览面板、逐帧告警文案 |
| `PetDesk/App/AppEnvironment.swift` | 预览数据源、视频导入入口 |
| `PetDeskTests/PoseFrameSetProcessorTests.swift` | 色彩归一化与诊断测试 |
| `PetDeskTests/AppEnvironmentTests.swift` | 预览数据源与导入入口回归 |
| `Checks/main.swift` | 归一化语义断言（如色彩迁移保护阈值） |
| `docs/architecture/overview.md` | 管线阶段与视频抽帧契约更新（随实现同步） |
