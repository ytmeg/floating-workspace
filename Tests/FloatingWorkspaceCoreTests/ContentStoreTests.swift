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

    func testDisabledPersistedImageModeOpensAsNoteWithoutSaving() throws {
        var persisted = WorkspaceContent.default
        persisted.selectedMode = .image
        persisted.noteText = "保留正文"
        let scheduler = ManualSaveScheduler()
        let saver = ControlledWorkspaceSaver()

        let store = try ContentStore(
            loader: FakeWorkspaceLoader(content: persisted),
            scheduler: scheduler,
            saver: saver
        )

        XCTAssertEqual(store.content.selectedMode, .note)
        XCTAssertEqual(store.content.noteText, "保留正文")
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(scheduler.delays.isEmpty)
        XCTAssertTrue(saver.snapshots.isEmpty)
    }

    func testPersistedWebModeOpensAsWebWithoutSaving() throws {
        var persisted = WorkspaceContent.default
        persisted.selectedMode = .web
        persisted.noteText = "保留正文"
        let scheduler = ManualSaveScheduler()
        let saver = ControlledWorkspaceSaver()

        let store = try ContentStore(
            loader: FakeWorkspaceLoader(content: persisted),
            scheduler: scheduler,
            saver: saver
        )

        XCTAssertEqual(store.content.selectedMode, .web)
        XCTAssertEqual(store.content.noteText, "保留正文")
        XCTAssertFalse(store.isDirty)
        XCTAssertTrue(scheduler.delays.isEmpty)
        XCTAssertTrue(saver.snapshots.isEmpty)
    }

    func testDisabledPersistedModeLeavesStoredFileUntouchedUntilNextSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("workspace-v1.json")
        var persisted = WorkspaceContent.default
        persisted.selectedMode = .image
        try WorkspaceFileStore(fileURL: file).save(persisted)
        let original = try Data(contentsOf: file)

        let store = try ContentStore(fileURL: file)

        XCTAssertEqual(store.content.selectedMode, .note)
        XCTAssertEqual(try Data(contentsOf: file), original)
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
