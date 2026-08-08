import AppKit
import UniformTypeIdentifiers
import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// 托盘「拖出文件」的行为测试：拖拽 pasteboard 必须携带真实的 file:// 路径
/// （Finder/微信/QQ 据此解析文件），并为图片等目标注册内容 UTI 表示；
/// 复制/移动模式的拖拽操作掩码按用户选择返回。
final class ShelfDragOutTests: XCTestCase {
  func testPasteboardProviderRegistersFileURLAndImageUTI() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.png")
    let (item, provider) = ShelfDragOutPasteboard.makeItem(for: url)

    XCTAssertNotNil(provider, "图片文件应注册内容 UTI 数据提供者，供微信/QQ 等按内容消费的 app 使用")
    let types = item.types
    XCTAssertTrue(
      types.contains(.fileURL),
      "拖拽 pasteboard 必须携带 public.file-url，否则 Finder 无法识别为文件拖拽。实际: \(types)")
    XCTAssertTrue(
      types.contains(NSPasteboard.PasteboardType(UTType.png.identifier)),
      "图片文件还需注册内容 UTI，否则微信/QQ 等按内容消费的 app 无法预览。实际: \(types)")
  }

  func testFileURLStringIsRealPath() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.png")
    let (item, _) = ShelfDragOutPasteboard.makeItem(for: url)

    XCTAssertEqual(
      item.string(forType: .fileURL),
      url.absoluteString,
      "必须提供真实 file:// URL 字符串，而非临时副本路径")
  }

  func testNonImageFileStillCarriesFileURL() {
    let url = URL(fileURLWithPath: "/tmp/PetDesk-拖出测试.txt")
    let (item, provider) = ShelfDragOutPasteboard.makeItem(for: url)

    XCTAssertNil(provider, "非图片文件只注册 file-url，不注册内容数据")
    XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
  }

  func testOperationMaskForCopyMode() {
    XCTAssertEqual(ShelfDragOutPasteboard.operationMask(for: .copy), .copy)
  }

  func testOperationMaskForMoveMode() {
    XCTAssertEqual(ShelfDragOutPasteboard.operationMask(for: .move), [.copy, .move])
  }
}
