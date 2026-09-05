# PetDesk 性能优化结果（2026-09-05）

## 本次范围

本轮只处理低风险、可回归验证的优化：

- CALayer 多帧动画使用 CGImage-only 帧缓存，避免为未使用的 SwiftUI 路径创建 NSImage 包装。
- 手动钉住状态仍锁定宠物外观，但继续消费 CPU 指标，更新负载平均值和动画播放速度。
- `petScale`、`animationSpeedMultiplier` 的 UserDefaults 写入增加 300ms debounce；停止应用时 flush。
- Todo 连续修改增加 300ms debounce，仅保存最后一个快照；停止应用时 flush。
- 移除未使用的 `acceptsMouseMovedEvents`，避免接收无意义的鼠标移动事件。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 定向回归测试 | 4/4 通过 |
| `PetDeskTests` | 157/157 通过 |
| `PetDeskUITests` | 7/7 通过 |
| `make lint` | 通过 |
| `swift run PetDeskCoreChecks` | 通过 |
| Debug / Release build | 通过 |
| `make verify` | 通过 |

## Release 运行态采样

命令：

```bash
xcodebuild -project PetDesk.xcodeproj -scheme PetDesk \
  -configuration Release -derivedDataPath /tmp/PetDeskAuditDerived \
  build CODE_SIGNING_ALLOWED=NO
scripts/measure-petdesk.sh \
  "/tmp/PetDeskAuditDerived/Build/Products/Release/PetDesk.app" 60 15
```

结果：

| 场景 | avg_cpu_pct | avg_rss_mb | peak_rss_mb |
| --- | ---: | ---: | ---: |
| 默认静态启动（Release，60 秒） | 0.07 | 123 | 123 |

该测量没有通过 Settings 导入八帧姿势，因此不能作为多帧 CALayer 动画专项基线。现有 2026-08 记录中的真实八帧场景仍是后续重复测量的参考基线。

## 尚未纳入本轮的项目

- `customPoseCells` 与完整 `avatarSpritesheet` 的重复像素持有：需要重新设计姿势帧的按需加载和清除流程。
- 动态 CALayer 阴影的合成成本：需要 Instruments 对比动态阴影、固定 shadowPath 和预烘焙阴影。
- 三个独立的一秒循环的 wakeup 成本：需要 Energy Log / Time Profiler 证据后再决定是否合并。
- Drag Shelf 的完整文件路径持久化：这首先是隐私与产品契约问题，不应只作为性能问题处理。
