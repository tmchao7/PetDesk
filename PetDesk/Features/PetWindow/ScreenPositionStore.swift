import AppKit

#if SWIFT_PACKAGE
  import PetDeskCore
#endif

@MainActor
final class ScreenPositionStore {
  private enum Keys {
    static let x = "petWindowX"
    static let y = "petWindowY"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func restore(size: NSSize, visibleFrames: [CGRect]) -> NSRect {
    let fallbackFrame = defaultFrame(size: size, visibleFrames: visibleFrames)
    guard defaults.object(forKey: Keys.x) != nil, defaults.object(forKey: Keys.y) != nil else {
      return fallbackFrame
    }
    let stored = NSRect(
      origin: NSPoint(x: defaults.double(forKey: Keys.x), y: defaults.double(forKey: Keys.y)),
      size: size
    )
    return ScreenPositionResolver.clamped(frame: stored, visibleFrames: visibleFrames)
  }

  func restore(size: NSSize, screens: [NSScreen]) -> NSRect {
    restore(size: size, visibleFrames: screens.map(\.visibleFrame))
  }

  func save(frame: NSRect) {
    defaults.set(frame.origin.x, forKey: Keys.x)
    defaults.set(frame.origin.y, forKey: Keys.y)
  }

  func reset() {
    defaults.removeObject(forKey: Keys.x)
    defaults.removeObject(forKey: Keys.y)
  }

  private func defaultFrame(size: NSSize, visibleFrames: [CGRect]) -> NSRect {
    guard let frame = visibleFrames.first else { return NSRect(origin: .zero, size: size) }
    return NSRect(
      x: frame.maxX - size.width - 24,
      y: frame.minY + 24,
      width: size.width,
      height: size.height
    )
  }

  private func defaultFrame(size: NSSize, screens: [NSScreen]) -> NSRect {
    defaultFrame(size: size, visibleFrames: screens.map(\.visibleFrame))
  }
}
