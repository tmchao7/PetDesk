# PetDesk

[![Release](https://img.shields.io/badge/下载-v0.1.0-blue)](https://github.com/tmchao7/PetDesk/releases/latest)

PetDesk is a native macOS 26 desktop companion. It animates an imported avatar in response to CPU load, coarse thermal pressure, user activity, focus sessions, and optional best-effort WeChat/QQ notification pulses.

## 安装（Install）

从 [Releases](https://github.com/tmchao7/PetDesk/releases/latest) 下载 `PetDesk-*.dmg`（约 0.8 MB），然后：

1. 打开 dmg，把 **PetDesk** 拖进 **Applications**
2. 首次启动：由于当前版本未签名（ad-hoc），macOS 会提示"无法验证开发者"——
   **右键 PetDesk.app → 打开 → 再点"打开"** 即可（只需一次）；
   或终端执行 `xattr -cr /Applications/PetDesk.app`
3. 启动后从菜单栏 🐾 图标进入设置，导入一张动漫风头像即可使用

> 无签名分发是开发阶段的轻量方案；正式签名 + 公证（无警告安装）将在
> Developer ID 证书就绪后随版本发布。

## 功能速览（Features）

- 透明悬浮桌宠：随 CPU 负载 / 温度 / 空闲 / 专注会话切换状态（精灵图静态显示）
- 气泡快捷动作：点击宠物 → 待办（可滚动、内联勾选）+ **专注 / 摸鱼 / 放松**
  （点击即钉住，不自动切换）
- 状态时长提醒：三种状态各自阈值 + 自定义文案（`{minutes}` 占位符）+ 气泡预览
- 逐状态姿势导入：专注 / 摸鱼 / 休息 各一张图（PNG/WebP，自动抠底）
- 待办列表、使用统计（最近 7 天柱状图）、桌宠大小、开机启动
- 空闲 CPU ≈0.26%，内存 ≈109 MB

## Requirements

- Apple silicon Mac running macOS 26
- Xcode 26 with its developer directory selected
- XcodeGen (`brew install xcodegen`)

## Development

```bash
make setup-git
make bootstrap
make generate
make test
make handoff-check
make run
```

The generated Xcode project is local output. `project.yml` is the reviewed project definition. The Swift package exists to test the non-UI core without generating an app bundle.

## Contributing

Repository rules are documented in `CONTRIBUTING.md`. Branch naming, Conventional Commits, hooks, pull requests, recovery, and release tagging are defined in `docs/development/git-workflow.md`. Coding agents must also follow `AGENTS.md` and their tool-specific entry file.

Agent-to-agent continuity is tracked through `docs/agent-handoff/CURRENT.md` and immutable session records. Read `docs/agent-handoff/README.md` before asking a new coding agent to continue the project.

## Privacy

All state stays on the Mac. PetDesk does not read notification bodies or contact names. The optional notification experiment inspects only a notification's source app and degrades to unsupported when the Accessibility tree is not usable.
