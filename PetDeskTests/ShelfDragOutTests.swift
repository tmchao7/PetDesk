import AppKit
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// 托盘「拖出文件」的行为测试：拖拽 pasteboard 必须同时携带
/// `public.file-url`（Finder 读取）与 `NSFilenamesPboardType` 路径数组
/// （微信/QQ 等 IM 目标读取），两者缺一对应目标就拒绝拖拽；
/// 复制/移动模式的拖拽操作掩码按用户选择返回。
final class ShelfDragOutTests: XCTestCase {
  private func pasteboard(for url: URL) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShelfDragOutTests.\(UUID())"))
    pasteboard.clearContents()
    pasteboard.writeObjects([ShelfDragOutPasteboard.makeWriter(for: url)])
    return pasteboard
  }

  func testPasteboardCarriesFileURLAndLegacyFilenamesForIMTargets() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.png")
    let pasteboard = pasteboard(for: url)

    let types = pasteboard.types ?? []
    XCTAssertTrue(
      types.contains(.fileURL),
      "拖拽 pasteboard 必须携带 public.file-url，否则 Finder 无法识别为文件拖拽。实际: \(types)")
    XCTAssertTrue(
      types.contains(ShelfDragOutPasteboard.filenamesType),
      "拖拽 pasteboard 必须携带 NSFilenamesPboardType，否则微信/QQ 等 IM 目标无反应。实际: \(types)")
  }

  func testFileURLAndFilenamesPointToRealPath() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.png")
    let pasteboard = pasteboard(for: url)

    XCTAssertEqual(
      pasteboard.string(forType: .fileURL),
      url.absoluteString,
      "file-url 必须是真实 file:// URL 字符串，而非临时副本路径")
    let paths = pasteboard.propertyList(forType: ShelfDragOutPasteboard.filenamesType) as? [String]
    XCTAssertEqual(paths, [url.path], "NSFilenamesPboardType 必须是真实路径数组")
  }

  func testNonImageFileStillProducesBothFileTypes() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.txt")
    let pasteboard = pasteboard(for: url)

    let types = pasteboard.types ?? []
    XCTAssertTrue(types.contains(.fileURL))
    XCTAssertTrue(types.contains(ShelfDragOutPasteboard.filenamesType))
  }

  func testAllowedOperationsLetSystemDecideMoveOrCopy() {
    // 源声明同时允许复制与移动，由系统/目标按 Finder 语义决定：
    // 同盘=移动、跨盘=复制、微信/QQ/邮件=复制（它们只接受复制）。
    XCTAssertEqual(ShelfDragOutPasteboard.allowedOperations, [.copy, .move])
  }
}
