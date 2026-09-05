import Foundation

public protocol TodoStoring: Sendable {
  func load() async -> [TodoItem]
  func save(_ items: [TodoItem]) async throws
}

public actor TodoStore: TodoStoring {
  private let fileManager: FileManager
  private let fileURL: URL

  public init(
    fileManager: FileManager = .default,
    directoryURL: URL? = nil
  ) throws {
    self.fileManager = fileManager
    if let directoryURL {
      self.fileURL = directoryURL.appendingPathComponent("todos.json")
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = applicationSupport.appendingPathComponent("PetDesk", isDirectory: true)
      self.fileURL = directory.appendingPathComponent("todos.json")
    }
  }

  public func load() -> [TodoItem] {
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let items = try? JSONDecoder().decode([TodoItem].self, from: data)
    else { return [] }
    return items
  }

  public func save(_ items: [TodoItem]) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(items)
    try data.write(to: fileURL, options: .atomic)
  }
}
