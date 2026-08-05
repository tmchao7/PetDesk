import Foundation

/// 拖拽缓存托盘的持久化：文件路径列表（UserDefaults）。
/// 重启恢复时会清理失效路径。
public final class DragShelfStore {
  private let defaults: UserDefaults
  private let key = "dragShelfItems"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// 读取全部条目，过滤掉已不存在的路径。
  public func load() -> [String] {
    let paths = defaults.stringArray(forKey: key) ?? []
    return paths.filter { FileManager.default.fileExists(atPath: $0) }
  }

  public func save(_ paths: [String]) {
    defaults.set(paths, forKey: key)
  }
}
