import Foundation

public struct RingBuffer<Element: Sendable>: Sendable {
  public private(set) var values: [Element] = []
  public let capacity: Int

  public init(capacity: Int) {
    self.capacity = max(capacity, 1)
  }

  public mutating func append(_ value: Element) {
    values.append(value)
    if values.count > capacity {
      values.removeFirst(values.count - capacity)
    }
  }

  public mutating func removeAll(keepingCapacity: Bool = true) {
    values.removeAll(keepingCapacity: keepingCapacity)
  }
}
