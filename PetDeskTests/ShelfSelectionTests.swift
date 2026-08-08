import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

/// 托盘多选行为测试：单击=单选，Command+单击=切换，Shift+单击=从锚点连选区间；
/// 拖拽集合=已选中行拖整组（按显示顺序）、未选中行只拖自身；删除/清空会清理选择。
final class ShelfSelectionTests: XCTestCase {
  private let items = ["/a", "/b", "/c", "/d"]

  @MainActor
  func testPlainClickSelectsSingleAndMovesAnchor() {
    let selection = ShelfSelection()
    selection.click(on: "/b", in: items, shift: false, command: false)
    XCTAssertEqual(selection.selectedPaths, ["/b"])
    selection.click(on: "/d", in: items, shift: false, command: false)
    XCTAssertEqual(selection.selectedPaths, ["/d"])
  }

  @MainActor
  func testCommandClickTogglesWithoutAffectingOthers() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.click(on: "/c", in: items, shift: false, command: true)
    selection.click(on: "/a", in: items, shift: false, command: true)
    XCTAssertEqual(selection.selectedPaths, ["/c"])
  }

  @MainActor
  func testShiftClickSelectsRangeFromAnchor() {
    let selection = ShelfSelection()
    selection.click(on: "/b", in: items, shift: false, command: false)
    selection.click(on: "/d", in: items, shift: true, command: false)
    XCTAssertEqual(selection.selectedPaths, ["/b", "/c", "/d"])
  }

  @MainActor
  func testShiftClickBackwardsSelectsContiguousRange() {
    let selection = ShelfSelection()
    selection.click(on: "/d", in: items, shift: false, command: false)
    selection.click(on: "/a", in: items, shift: true, command: false)
    XCTAssertEqual(selection.selectedPaths, ["/a", "/b", "/c", "/d"])
  }

  @MainActor
  func testShiftClickWithoutAnchorSelectsSingle() {
    let selection = ShelfSelection()
    selection.click(on: "/c", in: items, shift: true, command: false)
    XCTAssertEqual(selection.selectedPaths, ["/c"])
  }

  @MainActor
  func testDragPathsForSelectedRowReturnsWholeGroupInDisplayOrder() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.click(on: "/c", in: items, shift: false, command: true)
    XCTAssertEqual(selection.dragPaths(for: "/a", in: items), ["/a", "/c"])
  }

  @MainActor
  func testDragPathsForUnselectedRowReturnsOnlyThatRow() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.click(on: "/c", in: items, shift: false, command: true)
    XCTAssertEqual(selection.dragPaths(for: "/b", in: items), ["/b"])
  }

  @MainActor
  func testRemovePrunesSelectionAndAnchor() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.click(on: "/c", in: items, shift: false, command: true)
    selection.remove(["/a"])
    XCTAssertEqual(selection.selectedPaths, ["/c"])
    selection.remove(["/c"])
    XCTAssertTrue(selection.selectedPaths.isEmpty)
  }

  @MainActor
  func testPruneKeepsOnlyExistingItems() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.click(on: "/c", in: items, shift: false, command: true)
    selection.prune(keeping: ["/a", "/d"])
    XCTAssertEqual(selection.selectedPaths, ["/a"])
  }

  @MainActor
  func testClearEmptiesSelection() {
    let selection = ShelfSelection()
    selection.click(on: "/a", in: items, shift: false, command: false)
    selection.clear()
    XCTAssertTrue(selection.selectedPaths.isEmpty)
  }
}
