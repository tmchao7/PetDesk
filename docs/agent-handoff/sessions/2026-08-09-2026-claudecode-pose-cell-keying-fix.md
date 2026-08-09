# Agent Session Handoff

## Metadata

- Timestamp: 2026-08-09T20:26:16+0800
- Agent: claudecode
- Role: 抠底“白色部分变透明”根因修复 + 6 帧动画支持确认
- Objective: pose cell keying fix
- Status: ready
- Branch: fix/pose-cell-keying-leak
- Starting commit: 9103929
- Ending commit: 9103929（含本记录；handoff 提交后更新）

## Context Read

- `AGENTS.md`、`docs/agent-handoff/CURRENT.md` + 上一会话 `2026-08-08-1928-claudecode-deadcode-and-cpu-cleanup.md`
- `docs/prompts/doubao-sprite-prompt.md`、`docs/design/spritesheet-authoring.md`（用户 6 帧生成流程）
- `PetDesk/Features/Avatar/`：PoseCellProcessor / SpriteSheetSpec / SpriteSheetGenerator / GPTImage2Provider / AnimationFrameStore / AnimatedAvatarView
- `PetDesk/App/AppEnvironment.swift`、`PetDesk/Features/PetRender/PetView.swift + PetLayerRenderer.swift`、`PetDesk/Features/Settings/SettingsView.swift`
- `Checks/main.swift`（既有 PoseCellProcessor 检查）

## Work Performed

### 1. 6 帧动画支持确认（无代码改动，纯调查）

- 播放帧数来自 `customPoseCells[row].count`（importPose 导入的张数，1~8），非硬编码 8；
  专注/摸鱼/休息三行导入 6 张 → `multiFrameCount = 6` → 预切片 6 帧循环播放。
- 精灵图始终 8 列组装，多帧行用基准单元补位；播放只裁 `frameCount` 帧，补位列不参与。
- 重启后 `syncCustomPoseStateFromSpritesheet` 按“遇到基准单元即停”恢复帧数（6 帧行恢复 6 帧）。
- `importPose` 上限 `urls.count <= SpriteSheetSpec.columns`（8），6 无冲突。
- 结论：三个可导入状态（专注/摸鱼/休息）均支持 6 帧。注意点：文档所述“导入 8 帧长图
  自动切帧”在代码中不存在——长图单张导入只会得到 1 帧（静态）；必须按帧拆成多个文件多选导入。

### 2. 抠底“白色部分变透明”根因 + 修复（`9103929`）

- 根因（证据：对 picture.png 复算应用算法 + 逐像素统计）：
  - 背景为浅色（白/浅蓝灰）时，主体的白色/浅色部分（哆啦A梦肚皮/脸、受光面）与背景色
    距离 < 0.185，落在软抠 alpha 的软带内；
  - 边缘 flood 的通过阈值是软抠 alpha < 230（≈ 距离 0.185），会经 1-2px 泄漏通道
    （轮廓缺口、浅色道具/桌面接触、浅色轮廓直接贴背景）钻入主体，把整片连通浅色区域
    抠成透明；且软带像素在输出时按软 alpha 预乘，浅色主体细节变成半透明。
  - 实测 picture.png（2048×2048，浅蓝灰背景 + 浅色角色）：主体像素被清除 31.2%。
- 修复（PoseCellProcessor.makeCell 三处）：
  1. `floodBackground` 通过阈值 230 → 8：只清除“几乎等于背景色”的像素，软带像素不再
     参与 flood（浅色主体细节不被钻入）。
  2. 新增 `rescueFloodedInteriors`：flood 腐蚀 2 次 → 与图像边缘断开的腐蚀区域为种子
     （泄漏通道 ≤2px，腐蚀后消失）→ 在腐蚀 1 次的 flood 内扩张救回；腿间空隙等开放
     区域不会被救回。新增形态学 `erode` 辅助（边界缺邻域视为通过，全背景图才不会
     误判为内部种子——全品红图返回 nil 的既有检查靠此保持）。
  3. 新增 `keptSoftComponents`：非 flood 软带像素按 4-连通分组，组件最小跨度 ≥4px 的
     按主体细节保留不透明（浅色肚皮/受光面/内部阴影），细窄组件（抗锯齿边缘）清除。
- 实测修复后：picture.png 主体损失 31.2% → 0.9%；真实 makeCell 输出 192×208 单元
  92.3% 不透明、内部透明空洞 0。

## Decisions

- flood 阈值收窄到硬带（8）而不是放宽容差：浅色背景 + 浅色主体在颜色空间本就不可分，
  用连通性/几何（腐蚀 + 组件跨度）区分“背景连通”与“被主体包围”，优先保主体。
- 只保留“几乎等于背景色”的像素会被移除：白桌贴白肚皮（同为硬带）这类真正同色的
  情况仍然无法区分（颜色信息不存在），提示用户生成时用纯绿/纯品红背景。
- 不提交 `picture.png`（未跟踪，属用户资产；上会话记录已禁止提交）。
- 不改 6 帧相关代码：播放路径天然支持 1~8 帧。

## Verification

- `swift run PetDeskCoreChecks`：all checks passed（含新增 `checkPoseCellRescuesLeakedInterior`：
  白底蓝环带 2px 缺口 + 内部白色圆，泄漏进内部的白色必须保留不透明——修复前该检查失败）。
- `make lint`：passed（修了一处 swift format 换行警告）。
- `make test`：PetDeskTests 136 tests, 0 failures。
- `make verify`：全绿（含 Debug/Release 构建、禁止构造检查、PetDeskUITests 7 tests——
  本次 UI runner 环境恢复正常，此前会话记录的 runner 崩溃未复现）。
- 未执行：无（verify 全流程已跑）。

## Review and Debug Findings

- 旧逻辑的“内部同色像素保留”依赖 flood 无法进入（被强主体包围），但 AI 生成图
  的 1-2px 轮廓缺口/浅色道具接触让 flood 能钻入，旧保护形同虚设。
- 软带预乘输出（半透明边缘）对“浅色主体细节”是错误假设：浅色细节与抗锯齿边缘
  在颜色上不可分，只能靠组件宽度区分（≥4px = 细节，否则 = 边缘）。
- 泄漏救回的腐蚀-种子-扩张组合天然避免了“腿间空隙被救回”的误报：开放区域在
  腐蚀 2 次后仍与边缘连通。

## Open Issues and Risks

- 白桌贴白肚皮（同色硬带）等极端同色场景仍会吃主体——颜色信息不存在，无算法可救；
  提示用户生成时保证纯色背景与角色颜色明显分离（文档已强调“角色不要使用绿色”）。
- `keptSoftComponents` 的 4px 跨度阈值按典型源图（≥256px）标定；极小图（<64px）
  下抗锯齿带可能 ≥4px，有把边缘当主体的风险（当前导入路径源图 ≥256px，不受影响）。
- 6 帧生成流程下 `docs/prompts/doubao-sprite-prompt.md` 仍写 8 帧动作脚本：功能兼容
  （1~8 帧），如用户希望文档同步为 6 帧可后续更新；文档“导入长图自动切帧”表述与
  代码不符（需按帧拆文件导入）。

## Next Actions

1. Owner：重新导入专注/摸鱼/休息的 6 帧姿势图，验证动画为 ×6 循环且浅色部分不再透明。
2. Owner：可选——把 doubao 提示词文档从 8 帧改成 6 帧动作脚本（或补一句“导入需按帧拆文件”）。
3. 推送分支（pre-push hook 会跑 make verify，本次环境已全绿，无需 --no-verify）。

## Git State

- Branch: `fix/pose-cell-keying-leak`（未推送；main 上本轮无改动）。
- Commits: `9103929` fix(avatar): stop chroma key from eating light-colored character parts。
- Working tree: `picture.png` 未跟踪（禁止提交）；handoff 待随本记录提交。
