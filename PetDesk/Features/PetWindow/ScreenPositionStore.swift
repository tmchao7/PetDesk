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

  func restore(size: NSSize, screens: [NSScreen]) -> NSRect {
    let visibleFrames = screens.map(\.visibleFrame)
    let fallbackFrame = defaultFrame(size: size, screens: screens)
    guard defaults.object(forKey: Keys.x) != nil, defaults.object(forKey: Keys.y) != nil else {
      return fallbackFrame
    }
    let stored = NSRect(
      origin: NSPoint(x: defaults.double(forKey: Keys.x), y: defaults.double(forKey: Keys.y)),
      size: size
    )
    return ScreenPositionResolver.clamped(frame: stored, visibleFrames: visibleFrames)
  }

  func save(frame: NSRect) {
    defaults.set(frame.origin.x, forKey: Keys.x)
    defaults.set(frame.origin.y, forKey: Keys.y)
  }

  func reset() {
    defaults.removeObject(forKey: Keys.x)
    defaults.removeObject(forKey: Keys.y)
  }

  private func defaultFrame(size: NSSize, screens: [NSScreen]) -> NSRect {
    guard let screen = screens.first else { return NSRect(origin: .zero, size: size) }
    return NSRect(
      x: screen.visibleFrame.maxX - size.width - 24,
      y: screen.visibleFrame.minY + 24,
      width: size.width,
      height: size.height
    )
  }
}
