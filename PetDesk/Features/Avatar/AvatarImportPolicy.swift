import Foundation

public enum AvatarImportError: Error, Sendable, Equatable {
  case fileTooLarge
  case unsupportedType
  case unreadableImage
  case encodingFailed
}

public struct AvatarImportPolicy: Sendable, Equatable {
  public let maximumByteCount: Int
  public let maximumPixelSize: Int
  public let allowedExtensions: Set<String>

  public init(
    maximumByteCount: Int = 20 * 1_024 * 1_024,
    maximumPixelSize: Int = 1_024,
    allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
  ) {
    self.maximumByteCount = maximumByteCount
    self.maximumPixelSize = maximumPixelSize
    self.allowedExtensions = allowedExtensions
  }

  public func validate(byteCount: Int, fileExtension: String) throws {
    guard byteCount <= maximumByteCount else { throw AvatarImportError.fileTooLarge }
    guard allowedExtensions.contains(fileExtension.lowercased()) else {
      throw AvatarImportError.unsupportedType
    }
  }
}
