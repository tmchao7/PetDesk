import Combine

/// 托盘文件多选状态（标准 macOS 列表选择语义）：
/// - 单击：单选，并把该行设为「锚点」。
/// - Command+单击：切换该行选中状态，并把该行设为锚点。
/// - Shift+单击：从锚点连选到该行的区间（锚点不变，可连续扩展）。
/// - 拖拽：拖的是已选中行 → 整组拖出（按显示顺序）；拖未选中行 → 只拖该行。
///
/// AppKit 行在 mouseDown/mouseUp 里调用 `click`/`dragPaths`；SwiftUI 观察
/// `selectedPaths` 重绘高亮。选择是托盘面板的临时 UI 状态，不进入 PetStateMachine。
/// 纯逻辑类（非 actor）：所有调用方都在主线程（AppKit 鼠标事件 / SwiftUI），
/// 不跨 actor 传递，无需 actor 隔离。
final class ShelfSelection: ObservableObject {
  @Published private(set) var selectedPaths: Set<String> = []
  private var anchorPath: String?

  func click(on path: String, in items: [String], shift: Bool, command: Bool) {
    if shift {
      guard
        let anchor = anchorPath,
        let start = items.firstIndex(of: anchor),
        let end = items.firstIndex(of: path)
      else {
        // 无锚点（或锚点已被移除）：退化为单选。
        selectedPaths = [path]
        anchorPath = path
        return
      }
      selectedPaths = Set(items[min(start, end)...max(start, end)])
      // 锚点保持不动：连续 Shift+单击从同一锚点扩展区间。
    } else if command {
      if selectedPaths.contains(path) {
        selectedPaths.remove(path)
      } else {
        selectedPaths.insert(path)
      }
      anchorPath = path
    } else {
      selectedPaths = [path]
      anchorPath = path
    }
  }

  /// 拖拽集合：拖的是已选中行 → 整组（按托盘显示顺序）；否则只拖这一行。
  func dragPaths(for path: String, in items: [String]) -> [String] {
    guard selectedPaths.contains(path) else { return [path] }
    return items.filter { selectedPaths.contains($0) }
  }

  func isSelected(_ path: String) -> Bool {
    selectedPaths.contains(path)
  }

  /// 删除条目后清理选择（含锚点）。
  func remove(_ paths: Set<String>) {
    selectedPaths.subtract(paths)
    if let anchor = anchorPath, paths.contains(anchor) {
      anchorPath = nil
    }
  }

  /// 托盘内容变化后，去掉已不存在的选中项。
  func prune(keeping items: Set<String>) {
    selectedPaths = selectedPaths.intersection(items)
    if let anchor = anchorPath, !items.contains(anchor) {
      anchorPath = nil
    }
  }

  func clear() {
    selectedPaths = []
    anchorPath = nil
  }
}
