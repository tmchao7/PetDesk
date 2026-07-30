import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class AvatarRepositoryTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AvatarRepositoryTests-\(UUID().uuidString)")
  }

  override func tearDown() {
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    super.tearDown()
  }

  func testImportAvatarWritesResizedPNG() async throws {
    let sourceURL = try writeTestPNG(size: 64)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    let result = try await repo.importAvatar(from: sourceURL)

    XCTAssertEqual(result.lastPathComponent, "avatar.png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
  }

  func testImportAvatarReplacesExisting() async throws {
    let sourceURL = try writeTestPNG(size: 64)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    _ = try await repo.importAvatar(from: sourceURL)
    _ = try await repo.importAvatar(from: sourceURL)

    let avatarURL = tempDirectory.appendingPathComponent("avatar.png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: avatarURL.path))
  }

  func testImportRejectsUnreadableFile() async throws {
    let garbageURL = tempDirectory.appendingPathComponent("fake.png")
    try FileManager.default.createDirectory(
      at: tempDirectory, withIntermediateDirectories: true)
    try Data([0xFF, 0xD8, 0x00, 0x00]).write(to: garbageURL)

    let repo = try AvatarRepository(directoryURL: tempDirectory)

    do {
      _ = try await repo.importAvatar(from: garbageURL)
      XCTFail("Expected unreadableImage error")
    } catch AvatarImportError.unreadableImage {
      // Expected
    }
  }

  func testTempFileCleanedUpAfterSuccess() async throws {
    let sourceURL = try writeTestPNG(size: 64)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    _ = try await repo.importAvatar(from: sourceURL)

    let tempFile = tempDirectory.appendingPathComponent("avatar-import.png")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: tempFile.path),
      "temporary import file should be removed after successful import")
  }

  // MARK: - Helpers

  private func writeTestPNG(size: Int) throws -> URL {
    try FileManager.default.createDirectory(
      at: tempDirectory, withIntermediateDirectories: true)
    let url = tempDirectory.appendingPathComponent("source.png")
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue),
      let image = context.makeImage()
    else {
      throw NSError(domain: "test", code: 1)
    }
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw NSError(domain: "test", code: 2)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 3)
    }
    return url
  }
}
