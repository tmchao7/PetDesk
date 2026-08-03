import ImageIO
import UniformTypeIdentifiers
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

  private func makeSpritesheetFile(
    in directory: URL,
    name: String = "sheet.png",
    sparseCell: (row: Int, column: Int)? = nil,
    opaque: Bool = false
  ) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let bitmapInfo = CGBitmapInfo(
      rawValue: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast)
        .rawValue)
    let width = SpritesheetImportPolicy.expectedWidth
    let height = SpritesheetImportPolicy.expectedHeight
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { throw NSError(domain: "test", code: 10) }
    if opaque {
      context.setFillColor(CGColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    } else {
      context.clear(CGRect(x: 0, y: 0, width: width, height: height))
      let frameW = Int(SpriteSheetSpec.frameWidth)
      let frameH = Int(SpriteSheetSpec.frameHeight)
      let blockSize = 64
      for row in AnimationRow.allCases {
        for column in 0..<row.frameCount {
          if let sparseCell, sparseCell.row == row.rawValue, sparseCell.column == column {
            continue
          }
          context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
          let visualX = column * frameW + 64
          let visualY = row.rawValue * frameH + 64
          context.fill(
            CGRect(
              x: visualX,
              y: height - visualY - blockSize,
              width: blockSize,
              height: blockSize
            )
          )
        }
      }
    }
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "test", code: 11) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 12)
    }
    return url
  }

  private func makeNonUniformOpaqueFile(in directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("opaque.png")
    let width = SpritesheetImportPolicy.expectedWidth
    let height = SpritesheetImportPolicy.expectedHeight
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { throw NSError(domain: "test", code: 20) }
    let halfW = width / 2
    let halfH = height / 2
    let quadrants: [(CGRect, CGFloat, CGFloat, CGFloat)] = [
      (CGRect(x: 0, y: 0, width: halfW, height: halfH), 1, 0, 0),
      (CGRect(x: halfW, y: 0, width: halfW, height: halfH), 0, 1, 0),
      (CGRect(x: 0, y: halfH, width: halfW, height: halfH), 0, 0, 1),
      (CGRect(x: halfW, y: halfH, width: halfW, height: halfH), 1, 1, 1),
    ]
    for (rect, r, g, b) in quadrants {
      context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
      context.fill(rect)
    }
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "test", code: 21) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 22)
    }
    return url
  }

  private func makeSquareGridFile(in directory: URL, size: Int = 1024) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("grid.png")
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue
      )
    else { throw NSError(domain: "test", code: 30) }
    context.setFillColor(CGColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let cellW = size / 8
    let cellH = size / 8
    let blockSize = min(cellW, cellH) / 2
    for row in 0..<8 {
      for column in 0..<8 {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        let visualX = column * cellW + (cellW - blockSize) / 2
        let visualY = row * cellH + (cellH - blockSize) / 2
        context.fill(
          CGRect(
            x: visualX,
            y: size - visualY - blockSize,
            width: blockSize,
            height: blockSize
          )
        )
      }
    }
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "test", code: 31) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "test", code: 32)
    }
    return url
  }

  func testImportSpritesheetValidPNG() async throws {
    let sourceURL = try makeSpritesheetFile(in: tempDirectory)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    let sheet = try await repo.importSpritesheet(from: sourceURL)

    XCTAssertEqual(sheet.width, 1536, "imported sheet should keep its dimensions")
    XCTAssertEqual(sheet.height, 1664)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: tempDirectory.appendingPathComponent("spritesheet.png").path),
      "valid sheet should be persisted as spritesheet.png")
    let loaded = await repo.loadSpritesheet()
    XCTAssertNotNil(loaded, "persisted sheet should load back")
  }

  func testImportSpritesheetRejectsWrongSize() async throws {
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let sourceURL = tempDirectory.appendingPathComponent("small.png")
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue),
      let image = context.makeImage()
    else {
      XCTFail("could not build small PNG")
      return
    }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else {
      XCTFail("could not build small PNG destination")
      return
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      XCTFail("could not finalize small PNG")
      return
    }
    try (data as Data).write(to: sourceURL)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    do {
      _ = try await repo.importSpritesheet(from: sourceURL)
      XCTFail("wrong-size sheet should be rejected")
    } catch SpritesheetImportError.invalidDimensions {
      // Expected.
    }
  }

  func testImportSpritesheetRejectsNonUniformOpaquePNG() async throws {
    let sourceURL = try makeNonUniformOpaqueFile(in: tempDirectory)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    do {
      _ = try await repo.importSpritesheet(from: sourceURL)
      XCTFail("non-uniform opaque sheet should be rejected")
    } catch SpritesheetImportError.missingAlpha {
      // Expected.
    }
  }

  func testImportSpritesheetNormalizesSquareGrid() async throws {
    let sourceURL = try makeSquareGridFile(in: tempDirectory)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    let sheet = try await repo.importSpritesheet(from: sourceURL)

    XCTAssertEqual(sheet.width, 1536, "square grid should normalize to 1536 wide")
    XCTAssertEqual(sheet.height, 1664, "square grid should normalize to 1664 tall")
    let loaded = await repo.loadSpritesheet()
    XCTAssertNotNil(loaded, "normalized sheet should persist")
  }

  func testImportSpritesheetRejectsSparseUsedCell() async throws {
    let sourceURL = try makeSpritesheetFile(in: tempDirectory, sparseCell: (row: 0, column: 0))
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    do {
      _ = try await repo.importSpritesheet(from: sourceURL)
      XCTFail("sparse used cell should be rejected")
    } catch SpritesheetImportError.sparseCell(let row, let column) {
      XCTAssertEqual(row, 0)
      XCTAssertEqual(column, 0)
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

  // MARK: - AvatarCropper

  func testCropProducesSquareOutput() throws {
    let image = try makeTestCGImage(width: 200, height: 150)

    let cropped = AvatarCropper.crop(
      image: image,
      viewSize: 100,
      panOffset: .zero,
      zoomScale: 1.0,
      outputSize: 64
    )

    XCTAssertNotNil(cropped)
    XCTAssertEqual(cropped?.width, 64)
    XCTAssertEqual(cropped?.height, 64)
  }

  func testCropWithZoomProducesSmallerSourceRegion() throws {
    let image = try makeTestCGImage(width: 200, height: 200)

    let croppedNormal = AvatarCropper.crop(
      image: image, viewSize: 100, panOffset: .zero, zoomScale: 1.0, outputSize: 64)
    let croppedZoomed = AvatarCropper.crop(
      image: image, viewSize: 100, panOffset: .zero, zoomScale: 2.0, outputSize: 64)

    XCTAssertNotNil(croppedNormal)
    XCTAssertNotNil(croppedZoomed)
    // Both should produce 64x64 output
    XCTAssertEqual(croppedZoomed?.width, 64)
  }

  // MARK: - Save / Reset

  func testSaveAvatarWritesPNG() async throws {
    let image = try makeTestCGImage(width: 64, height: 64)
    let repo = try AvatarRepository(directoryURL: tempDirectory)

    let result = try await repo.saveAvatar(image)

    XCTAssertEqual(result.lastPathComponent, "avatar.png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
  }

  func testResetAvatarRemovesFile() async throws {
    let sourceURL = try writeTestPNG(size: 64)
    let repo = try AvatarRepository(directoryURL: tempDirectory)
    _ = try await repo.importAvatar(from: sourceURL)
    let avatarURL = await repo.avatarURL
    XCTAssertTrue(FileManager.default.fileExists(atPath: avatarURL.path))

    try await repo.resetAvatar()

    XCTAssertFalse(FileManager.default.fileExists(atPath: avatarURL.path))
  }

  func testResetAvatarIsNoOpWhenNoAvatar() async throws {
    let repo = try AvatarRepository(directoryURL: tempDirectory)
    try await repo.resetAvatar()
    // Should not throw
  }

  // MARK: - Helpers

  private func makeTestCGImage(width: Int, height: Int) throws -> CGImage {
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo.rawValue),
      let image = context.makeImage()
    else {
      throw NSError(domain: "test", code: 1)
    }
    return image
  }

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
