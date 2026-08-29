# PetDesk

[![Release](https://img.shields.io/badge/下载-v2.1.0-blue)](https://github.com/tmchao7/PetDesk/releases/latest)

PetDesk is a **native macOS 26 desktop companion** — 原生、轻量、安静。
It animates an imported avatar in response to CPU load, coarse thermal pressure,
user activity, focus sessions, and optional best-effort WeChat/QQ notification pulses.

## 为什么选 PetDesk（Why PetDesk）

- **原生**：纯 Swift + SwiftUI/AppKit 构建，无 Electron、无运行时、无沙盒膨胀——
  安装包仅 **2.5 MB**（`.dmg` 压缩后约 2.6 MB）
- **轻量**：空闲 CPU **≈ 1%**、应用自身内存 **≈ 40 MB**（RSS 约 120 MB 含共享库）——
  不到 Electron 同类应用（通常 200-500 MB）的三分之一
- **安静**：无自动更新、无遥测、无后台进程；所有数据只留在你的 Mac 上
- **透明**：真透明悬浮窗，只有角色本身，没有卡片边框

## 安装（Install）

从 [Releases](https://github.com/tmchao7/PetDesk/releases/latest) 下载 `PetDesk-*.dmg`（约 2.6 MB），然后：

```bash
# 1. 挂载 dmg 并复制到 Applications
hdiutil attach ~/Downloads/PetDesk-2.1.0.dmg
cp -R "/Volumes/PetDesk/PetDesk.app" /Applications/
hdiutil detach /Volumes/PetDesk

# 2. 清除 Gatekeeper 隔离标记（未签名应用必需；若提示"已损坏"就是这个原因）
xattr -cr /Applications/PetDesk.app

# 3. 启动
open /Applications/PetDesk.app
```

或拖拽安装后只执行第 2 步的 `xattr -cr`。启动后从菜单栏 🐾 图标进入设置，导入一张动漫风头像即可使用。

> 当前版本未签名（ad-hoc），macOS 会拦截并提示"已损坏/无法验证开发者"——
> 应用本身没坏，执行 `xattr -cr` 即可。正式签名 + 公证（零警告安装）将在
> Developer ID 证书就绪后随版本发布。

**仍提示"已损坏"？**（Still says "damaged"?）

```bash
# 签名可能在传输/解压中被破坏 → 重新本地签名后重试
codesign --force --deep --sign - /Applications/PetDesk.app
xattr -cr /Applications/PetDesk.app
open /Applications/PetDesk.app
```

支持 Apple Silicon（arm64）；Intel Mac 请等待 x86_64 构建。

## 功能速览（Features）

- 透明悬浮桌宠：随 CPU 负载 / 温度 / 空闲 / 专注会话切换状态
- **专注多帧动画**：为专注状态导入 1~8 张动作帧，循环播放且**速度随 CPU 变化**
  （RunCat 风格：CPU 越高敲键盘越快；5~30 帧/秒，上限防正反馈）
- 气泡快捷动作：点击宠物 → 待办（可滚动、内联勾选）+ **专注 / 摸鱼 / 放松**
  （点击即钉住，不自动切换）
- 状态时长提醒：三种状态各自阈值 + 自定义文案（`{minutes}` 占位符）+ 气泡预览
- 逐状态姿势导入：专注多帧 / 摸鱼 / 休息（PNG/WebP，自动抠底，白色不误删）
- 待办列表、使用统计（最近 7 天柱状图）、桌宠大小、开机启动
- **资源占用**：空闲 CPU ≈ **1%**、应用自身内存 ≈ **40 MB**、安装包 ≈ **2.6 MB**

## Requirements（系统要求）

- Apple silicon Mac running macOS 26（Apple 芯片 + macOS 26）
- Xcode 26 with its developer directory selected（Xcode 26，开发者目录已选择）
- XcodeGen (`brew install xcodegen`)

## Development（开发）

```bash
make setup-git
make bootstrap
make generate
make test
make handoff-check
make run
```

The generated Xcode project is local output. `project.yml` is the reviewed project definition. The Swift package exists to test the non-UI core without generating an app bundle.

（生成的 `PetDesk.xcodeproj` 是本地产物，不入库；`project.yml` 才是被评审的项目定义。SwiftPM 包用于在不生成 app bundle 的情况下测试非 UI 核心。）

## Contributing（贡献）

Repository rules are documented in `CONTRIBUTING.md`. Branch naming, Conventional Commits, hooks, pull requests, recovery, and release tagging are defined in `docs/development/git-workflow.md`. Coding agents must also follow `AGENTS.md` and their tool-specific entry file.

（仓库规则见 `CONTRIBUTING.md`；分支命名、Conventional Commits、hooks、PR、恢复与发版标记见 `docs/development/git-workflow.md`。编码 agent 还需遵守 `AGENTS.md` 及各自的工具入口文件。）

Agent-to-agent continuity is tracked through `docs/agent-handoff/CURRENT.md` and immutable session records. Read `docs/agent-handoff/README.md` before asking a new coding agent to continue the project.

（跨 agent 交接通过 `docs/agent-handoff/CURRENT.md` 与不可变会话记录追踪。让新 agent 继续项目前，先读 `docs/agent-handoff/README.md`。）

## Privacy（隐私）

All state stays on the Mac. PetDesk does not read notification bodies or contact names. The optional notification experiment inspects only a notification's source app and degrades to unsupported when the Accessibility tree is not usable.

（所有数据只留在你的 Mac 上。PetDesk 不读取消息正文或联系人姓名。可选的通知实验只检查通知的来源应用；辅助功能树不可用时自动降级为不支持。）
