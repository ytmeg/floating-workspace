import AppKit
import XCTest
@testable import FloatingWorkspace
@testable import FloatingWorkspaceCore

@MainActor
final class AppDelegateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testCleanStoreTerminatesImmediately() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)
        XCTAssertTrue(fixture.saver.snapshots.isEmpty)
    }

    func testDirtyStoreWaitsForSuccessfulFlushBeforeTermination() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        var replies: [Bool] = []
        delegate.terminationReplyHandler = { replies.append($0) }
        fixture.store.update { $0.noteText = "persist before quit" }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        XCTAssertTrue(fixture.store.isSaving)
        XCTAssertTrue(replies.isEmpty)
        fixture.saver.completeSuccess(at: 0)
        drainTerminationQueue()

        XCTAssertEqual(replies, [true])
        XCTAssertFalse(fixture.store.isDirty)
    }

    func testInflightSaveWaitsWithoutStartingDuplicateSave() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        var replies: [Bool] = []
        delegate.terminationReplyHandler = { replies.append($0) }
        fixture.store.update { $0.noteText = "in flight" }
        fixture.scheduler.fire()
        XCTAssertTrue(fixture.store.isSaving)

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        XCTAssertEqual(fixture.saver.snapshots.count, 1)
        XCTAssertTrue(replies.isEmpty)
        fixture.saver.completeSuccess(at: 0)
        drainTerminationQueue()

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(fixture.saver.snapshots.count, 1)
    }

    func testFailedTerminationFlushKeepsDirtyAndAllowsExplicitDiscard() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        var replies: [Bool] = []
        var failureAlert: NSAlert?
        delegate.terminationReplyHandler = { replies.append($0) }
        delegate.alertPresenter = { alert in
            failureAlert = alert
            return .alertSecondButtonReturn
        }
        fixture.store.update { $0.noteText = "do not lose this" }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        fixture.saver.completeFailure(at: 0)
        drainTerminationQueue()

        let alert = try XCTUnwrap(failureAlert)
        XCTAssertEqual(alert.buttons.map(\.title), ["重试", "放弃未保存内容并退出"])
        XCTAssertEqual(replies, [true])
        XCTAssertTrue(fixture.store.isDirty)
        XCTAssertEqual(fixture.store.content.noteText, "do not lose this")
        guard case .failed = fixture.store.saveState else {
            return XCTFail("Expected failed save state")
        }
    }

    func testRetryAfterFailedTerminationFlushRetriesAndWaitsForSuccess() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        var replies: [Bool] = []
        var alertTitles: [String] = []
        delegate.terminationReplyHandler = { replies.append($0) }
        delegate.alertPresenter = { alert in
            alertTitles = alert.buttons.map(\.title)
            return .alertFirstButtonReturn
        }
        fixture.store.update { $0.noteText = "retry this save" }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        fixture.saver.completeFailure(at: 0)
        drainTerminationQueue()

        XCTAssertEqual(alertTitles, ["重试", "放弃未保存内容并退出"])
        XCTAssertEqual(fixture.saver.snapshots.count, 2)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertTrue(fixture.store.isDirty)
        fixture.saver.completeSuccess(at: 1)
        drainTerminationQueue()

        XCTAssertEqual(replies, [true])
        XCTAssertFalse(fixture.store.isDirty)
    }

    func testDevNullSaveFailureRetriesThenDiscardsWithoutClearingDirtyState() throws {
        let store = try ContentStore(fileURL: URL(fileURLWithPath: "/dev/null/workspace-v1.json"))
        let delegate = AppDelegate()
        delegate.store = store
        let failurePresented = expectation(description: "save failure presented twice")
        failurePresented.expectedFulfillmentCount = 2
        let terminationReplied = expectation(description: "termination reply")
        var alertCount = 0
        var replies: [Bool] = []
        delegate.alertPresenter = { alert in
            alertCount += 1
            XCTAssertEqual(alert.buttons.map(\.title), ["重试", "放弃未保存内容并退出"])
            XCTAssertTrue(store.isDirty)
            failurePresented.fulfill()
            return alertCount == 1 ? .alertFirstButtonReturn : .alertSecondButtonReturn
        }
        delegate.terminationReplyHandler = {
            replies.append($0)
            terminationReplied.fulfill()
        }
        store.update { $0.noteText = "must remain dirty" }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        wait(for: [failurePresented, terminationReplied], timeout: 2)

        XCTAssertEqual(alertCount, 2)
        XCTAssertEqual(replies, [true])
        XCTAssertTrue(store.isDirty)
        XCTAssertEqual(store.content.noteText, "must remain dirty")
        guard case .failed = store.saveState else {
            return XCTFail("Expected failed save state")
        }
    }

    func testApplicationWillTerminateStopsHotkey() throws {
        let delegate = AppDelegate()
        let first = HotkeyController {}
        try first.start()
        delegate.hotkeyController = first

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let second = HotkeyController {}
        try second.start()
        second.stop()
    }

    func testStoreURLUsesApplicationSupportAndIsolatedFileOverrides() throws {
        let support = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        XCTAssertEqual(
            AppDelegate.workspaceFileURL(environment: [:], applicationSupport: support).path,
            "/tmp/Application Support/FloatingWorkspace/workspace-v1.json"
        )
        XCTAssertEqual(
            AppDelegate.workspaceFileURL(
                environment: ["FLOATING_WORKSPACE_STORE_URL": "file:///tmp/Isolated%20Store/custom.json"],
                applicationSupport: support
            ).path,
            "/tmp/Isolated Store/custom.json"
        )
        XCTAssertEqual(
            AppDelegate.workspaceFileURL(
                environment: ["FLOATING_WORKSPACE_STORE_URL": "/dev/null/workspace-v1.json"],
                applicationSupport: support
            ).path,
            "/dev/null/workspace-v1.json"
        )
    }

    private func makeFixture() throws -> (
        scheduler: TerminationSaveScheduler,
        saver: TerminationWorkspaceSaver,
        store: ContentStore
    ) {
        let scheduler = TerminationSaveScheduler()
        let saver = TerminationWorkspaceSaver()
        let store = try ContentStore(
            loader: TerminationWorkspaceLoader(),
            scheduler: scheduler,
            saver: saver
        )
        return (scheduler, saver, store)
    }
}

private struct TerminationWorkspaceLoader: WorkspacePersisting {
    func load() throws -> WorkspaceLoadResult {
        WorkspaceLoadResult(content: .default, recoveryURL: nil)
    }

    func save(_ content: WorkspaceContent) throws {}
}

@MainActor
private final class TerminationSaveScheduler: SaveScheduling {
    private var action: (() -> Void)?

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let action = self.action
        self.action = nil
        action?()
    }
}

private final class TerminationWorkspaceSaver: WorkspaceSaving {
    private(set) var snapshots: [WorkspaceContent] = []
    private var completions: [(Result<Void, Error>) -> Void] = []

    func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void) {
        snapshots.append(content)
        completions.append(completion)
    }

    func completeSuccess(at index: Int) {
        completions[index](.success(()))
    }

    func completeFailure(at index: Int) {
        completions[index](.failure(NSError(
            domain: "AppDelegateTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test save failure"]
        )))
    }
}

@MainActor
private func drainTerminationQueue() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
