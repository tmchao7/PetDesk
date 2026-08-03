import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor AvatarRepository {
  private let fileManager: FileManager
  private let policy: AvatarImportPolicy
  private let spritesheetPolicy: SpritesheetImportPolicy
  private let directoryURL: URL

  public init(
    fileManager: FileManager = .default,
    policy: AvatarImportPolicy = AvatarImportPolicy(),
    spritesheetPolicy: SpritesheetImportPolicy = SpritesheetImportPolicy(),
    directoryURL: URL? = nil
  ) throws {
    self.fileManager = fileManager
    self.policy = policy
    self.spritesheetPolicy = spritesheetPolicy
    if let directoryURL {
      self.directoryURL = directoryURL
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      self.directoryURL = applicationSupport.appendingPathComponent("PetDesk", isDirectory: true)
    }
  }

  public var avatarURL: URL {
    directoryURL.appendingPathComponent("avatar.png")
  }

  public var spritesheetURL: URL {
    directoryURL.appendingPathComponent("spritesheet.png")
  }

  /// 加载精灵图（不存在时返回 nil）。
  public func loadSpritesheet() -> CGImage? {
    guard fileManager.fileExists(atPath: spritesheetURL.path) else { return nil }
    guard let source = CGImageSourceCreateWithURL(spritesheetURL as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// 保存精灵图。
  public func saveSpritesheet(_ image: CGImage) throws {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let temporaryURL = directoryURL.appendingPathComponent("spritesheet-import.png")
    defer { try? fileManager.removeItem(at: temporaryURL) }
    guard
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw AvatarImportError.encodingFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AvatarImportError.encodingFailed
    }
    if fileManager.fileExists(atPath: spritesheetURL.path) {
      _ = try fileManager.replaceItemAt(spritesheetURL, withItemAt: temporaryURL)
    } else {
      try fileManager.moveItem(at: temporaryURL, to: spritesheetURL)
    }
  }

  public func importAvatar(from sourceURL: URL) throws -> URL {
    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
    try policy.validate(
      byteCount: values.fileSize ?? 0,
      fileExtension: sourceURL.pathExtension
    )
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw AvatarImportError.unreadableImage
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: policy.maximumPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw AvatarImportError.unreadableImage
    }

    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let temporaryURL = directoryURL.appendingPathComponent("avatar-import.png")
    defer { try? fileManager.removeItem(at: temporaryURL) }
    guard
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw AvatarImportError.encodingFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AvatarImportError.encodingFailed
    }

    if fileManager.fileExists(atPath: avatarURL.path) {
      _ = try fileManager.replaceItemAt(avatarURL, withItemAt: temporaryURL)
    } else {
      try fileManager.moveItem(at: temporaryURL, to: avatarURL)
    }
    return avatarURL
  }

  public func loadSourceImage(from sourceURL: URL) throws -> CGImage {
    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
    try policy.validate(
      byteCount: values.fileSize ?? 0,
      fileExtension: sourceURL.pathExtension
    )
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw AvatarImportError.unreadableImage
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: policy.maximumPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw AvatarImportError.unreadableImage
    }
    return image
  }

  public func saveAvatar(_ image: CGImage) throws -> URL {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let temporaryURL = directoryURL.appendingPathComponent("avatar-import.png")
    defer { try? fileManager.removeItem(at: temporaryURL) }
    guard
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else { throw AvatarImportError.encodingFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AvatarImportError.encodingFailed
    }

    if fileManager.fileExists(atPath: avatarURL.path) {
      _ = try fileManager.replaceItemAt(avatarURL, withItemAt: temporaryURL)
    } else {
      try fileManager.moveItem(at: temporaryURL, to: avatarURL)
    }
    return avatarURL
  }

  public func resetAvatar() throws {
    guard fileManager.fileExists(atPath: avatarURL.path) else { return }
    try fileManager.removeItem(at: avatarURL)
  }

  /// 删除精灵图（重置头像时清理）。
  public func deleteSpritesheet() throws {
    guard fileManager.fileExists(atPath: spritesheetURL.path) else { return }
    try fileManager.removeItem(at: spritesheetURL)
  }

  /// 校验并导入用户自备的精灵图（PNG/WebP，1536×1664，透明背景）。
  public func importSpritesheet(from sourceURL: URL) throws -> CGImage {
    let image = try spritesheetPolicy.validate(url: sourceURL)
    try saveSpritesheet(image)
    return image
  }
}
