import XCTest

#if SWIFT_PACKAGE
  @testable import PetDeskCore
#else
  @testable import PetDesk
#endif

final class WindowDragPersistenceTests: XCTestCase {
  func testWindowMovesAreNotPersistedDuringUserDrag() {
    var gate = PetWindowDragPersistenceGate()

    XCTAssertTrue(gate.shouldPersistWindowMove)

    gate.beginUserDrag()
    XCTAssertFalse(gate.shouldPersistWindowMove)

    gate.endUserDrag()
    XCTAssertTrue(gate.shouldPersistWindowMove)
  }
}
