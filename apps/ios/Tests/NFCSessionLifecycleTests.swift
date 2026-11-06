import XCTest
@testable import NFCProbeCore

final class NFCSessionLifecycleTests: XCTestCase {
    func testCloseRequestDoesNotEnableRetryBeforeSystemCallback() {
        var state = NFCSessionLifecycle()
        let id = UUID()
        XCTAssertTrue(state.begin(id: id))
        state.becameActive(id: id)
        state.requestEnd(id: id)
        XCTAssertEqual(state.phase, .closing)
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.begin(id: UUID()))
        state.becameActive(id: id) // Late activation must not reopen closing state.
        XCTAssertEqual(state.phase, .closing)
        state.didEnd(id: id)
        XCTAssertEqual(state.phase, .ended)
        XCTAssertTrue(state.canStart)
    }

    func testSystemCancelDuringOpeningEndsWithoutExplicitClose() {
        var state = NFCSessionLifecycle()
        let id = UUID()
        state.begin(id: id)
        state.didEnd(id: id)
        XCTAssertEqual(state.phase, .ended)
        state.requestEnd(id: id)
        XCTAssertEqual(state.phase, .ended)
    }

    func testPreviousSessionCallbacksCannotChangeNewSession() {
        var state = NFCSessionLifecycle()
        let old = UUID(), current = UUID()
        state.begin(id: old)
        state.didEnd(id: old)
        state.begin(id: current)
        state.didEnd(id: old)
        state.becameActive(id: old)
        state.requestEnd(id: old)
        XCTAssertEqual(state.phase, .opening)
        XCTAssertFalse(state.canStart)
        state.becameActive(id: current)
        XCTAssertEqual(state.phase, .active)
    }
}
