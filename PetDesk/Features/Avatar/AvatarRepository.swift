import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor AvatarRepository {
  private let fileManager: FileManager
  private let policy: AvatarImportPolicy
  private let directoryURL: URL

  public init(
    fileManager: FileManager = .default,
    policy: AvatarImportPolicy = AvatarImportPolicy(),
    directoryURL: URL? = nil
  ) throws {
    self.fileManager = fileManager
    self.policy = policy
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
}
