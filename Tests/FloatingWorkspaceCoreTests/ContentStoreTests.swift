import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ContentStoreTests: XCTestCase {
    func testDebounceUses300msAndOnlyLatestText() throws {
        let doubles = try ContentStoreTestDoubles()
        doubles.store.update { $0.noteText = "first" }
        doubles.store.update { $0.noteText = "final" }
        XCTAssertEqual(doubles.scheduler.delays, [0.3, 0.3])
        doubles.scheduler.fire()
        XCTAssertEqual(doubles.saver.snapshots.map(\.noteText), ["final"])
    }

    func testEditDuringInflightSaveRequiresSecondSaveBeforeDirtyClears() throws {
        let doubles = try ContentStoreTestDoubles()
        doubles.store.update { $0.noteText = "first" }
        doubles.scheduler.fire()
        doubles.store.update { $0.noteText = "second" }
        doubles.saver.completeSuccess(at: 0)
        drainMainQueue()
        XCTAssertTrue(doubles.store.isDirty)
        XCTAssertEqual(doubles.saver.snapshots.map(\.noteText), ["first", "second"])
        doubles.saver.completeSuccess(at: 1)
        drainMainQueue()
        XCTAssertFalse(doubles.store.isDirty)
        XCTAssertEqual(doubles.store.saveState, .saved)
    }

    func testFailureKeepsContentDirtyAndVisibleError() throws {
        let doubles = try ContentStoreTestDoubles()
        doubles.store.update { $0.noteText = "keep me" }
        doubles.scheduler.fire()
        doubles.saver.completeFailure(at: 0)
        drainMainQueue()
        XCTAssertTrue(doubles.store.isDirty)
        XCTAssertEqual(doubles.store.content.noteText, "keep me")
        guard case .failed = doubles.store.saveState else {
            return XCTFail("Expected failed save state")
        }
    }

    func testFlushOnCleanStoreCompletesWithoutSaving() throws {
        let doubles = try ContentStoreTestDoubles()
        let expectation = expectation(description: "clean flush")
        doubles.store.flush { result in
            if case .success = result { expectation.fulfill() }
        }
        wait(for: [expectation], timeout: 0.1)
        XCTAssertTrue(doubles.saver.snapshots.isEmpty)
    }
}

@MainActor
private func drainMainQueue() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
