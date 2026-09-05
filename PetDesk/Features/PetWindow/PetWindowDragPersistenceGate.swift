import Foundation

/// Separates high-frequency interactive window movement from durable position
/// persistence. The final position is persisted when the user releases the
/// drag rather than once per mouse event.
struct PetWindowDragPersistenceGate {
  private(set) var isDragging = false

  var shouldPersistWindowMove: Bool { !isDragging }

  mutating func beginUserDrag() {
    isDragging = true
  }

  mutating func endUserDrag() {
    isDragging = false
  }
}
