import AppKit
import Foundation

@MainActor
public enum AvatarImageLoader {
  public static func load(from url: URL) -> NSImage? {
    NSImage(contentsOf: url)
  }
}
