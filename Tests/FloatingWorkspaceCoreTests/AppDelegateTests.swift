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

    override func tearDown() {
        NSApp.appearance = nil
        WorkspaceAppearance.acceptanceReduceTransparency = nil
        WorkspaceAppearance.acceptanceIncreaseContrast = nil
        super.tearDown()
    }

    func testAcceptanceOverridesParseLightDarkAndAccessibilityFlags() throws {
        AppDelegate.applyAcceptanceOverrides(environment: [
            "FLOATING_WORKSPACE_APPEARANCE": "light",
            "FLOATING_WORKSPACE_REDUCE_TRANSPARENCY": "1",
            "FLOATING_WORKSPACE_INCREASE_CONTRAST": "1"
        ])
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        XCTAssertEqual(WorkspaceAppearance.acceptanceReduceTransparency, true)
        XCTAssertEqual(WorkspaceAppearance.acceptanceIncreaseContrast, true)

        AppDelegate.applyAcceptanceOverrides(environment: [
            "FLOATING_WORKSPACE_APPEARANCE": "dark"
        ])
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertNil(WorkspaceAppearance.acceptanceReduceTransparency)
        XCTAssertNil(WorkspaceAppearance.acceptanceIncreaseContrast)
    }

    func testInvalidAcceptanceOverridesFallBackToSystemSettings() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        WorkspaceAppearance.acceptanceReduceTransparency = true
        WorkspaceAppearance.acceptanceIncreaseContrast = true

        AppDelegate.applyAcceptanceOverrides(environment: [
            "FLOATING_WORKSPACE_APPEARANCE": "sepia",
            "FLOATING_WORKSPACE_REDUCE_TRANSPARENCY": "true",
            "FLOATING_WORKSPACE_INCREASE_CONTRAST": "0"
        ])

        XCTAssertNil(NSApp.appearance)
        XCTAssertNil(WorkspaceAppearance.acceptanceReduceTransparency)
        XCTAssertNil(WorkspaceAppearance.acceptanceIncreaseContrast)
    }

    func testAcceptanceAccessibilityOverridesDriveCurrentPalette() throws {
        WorkspaceAppearance.acceptanceReduceTransparency = true
        WorkspaceAppearance.acceptanceIncreaseContrast = true

        let palette = WorkspaceAppearance.current(
            appearance: try XCTUnwrap(NSAppearance(named: .aqua))
        )

        XCTAssertFalse(palette.usesTransparency)
        XCTAssertTrue(palette.gradientColors.isEmpty)
        XCTAssertEqual(
            palette.borderColor,
            NSColor(srgbRed: 0x12 / 255, green: 0x19 / 255, blue: 0x26 / 255, alpha: 0.45)
        )
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

    func testTerminationFlushesWebDraftBeforeContentStoreFlush() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        let drafts = WebDraftStore(store: fixture.store)
        let controller = WebViewController(store: drafts)
        _ = controller.view
        let url = try XCTUnwrap(URL(string: "https://example.com/termination"))
        controller.webView.loadHTMLString(
            "<html><body><p id='text'>before quit</p></body></html>",
            baseURL: url
        )
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "加载完成"),
            object: controller.statusLabel
        )
        wait(for: [loaded], timeout: 5)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'draft saved at quit'", in: controller)
        delegate.webViewController = controller
        var replies: [Bool] = []
        delegate.terminationReplyHandler = { replies.append($0) }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        let saveDeadline = Date().addingTimeInterval(2)
        while fixture.saver.snapshots.isEmpty && Date() < saveDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        guard fixture.saver.snapshots.count == 1 else {
            return XCTFail("Expected exactly one ContentStore save after the web draft flush")
        }
        let snapshot = fixture.saver.snapshots[0]
        let key = "https://example.com/termination"
        XCTAssertTrue(snapshot.webDrafts[key]?.sanitizedBodyHTML.contains("draft saved at quit") == true)
        XCTAssertTrue(replies.isEmpty)
        fixture.saver.completeSuccess(at: 0)
        drainTerminationQueue()
        XCTAssertEqual(replies, [true])
        XCTAssertFalse(fixture.store.isDirty)
    }

    func testTerminationFlushesNewMutationMadeWithinEightHundredMillisecondsAfterIdleSave() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        let drafts = WebDraftStore(store: fixture.store)
        let controller = WebViewController(store: drafts)
        _ = controller.view
        let url = try XCTUnwrap(URL(string: "https://example.com/latest-termination-edit"))
        controller.webView.loadHTMLString(
            "<html><body><p id='text'>original</p></body></html>",
            baseURL: url
        )
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "加载完成"),
            object: controller.statusLabel
        )
        wait(for: [loaded], timeout: 5)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'first autosave'", in: controller)
        _ = try waitForDraft(containing: "first autosave", for: url, in: drafts)
        _ = try evaluate("document.getElementById('text').textContent = 'latest termination edit'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        delegate.webViewController = controller
        var replies: [Bool] = []
        delegate.terminationReplyHandler = { replies.append($0) }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        let saveDeadline = Date().addingTimeInterval(2)
        while fixture.saver.snapshots.isEmpty && Date() < saveDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        guard fixture.saver.snapshots.count == 1 else {
            return XCTFail("Expected exactly one ContentStore save after the latest draft flush")
        }
        let snapshot = fixture.saver.snapshots[0]
        let html = try XCTUnwrap(snapshot.webDrafts["https://example.com/latest-termination-edit"]?.sanitizedBodyHTML)
        XCTAssertTrue(html.contains("latest termination edit"))
        XCTAssertFalse(html.contains("first autosave"))
        fixture.saver.completeSuccess(at: 0)
        drainTerminationQueue()
        XCTAssertEqual(replies, [true])
    }

    func testTerminationDraftJavaScriptThrowRetainsDirtyAndAllowsRetryThenDiscard() throws {
        let fixture = try makeFixture()
        let delegate = AppDelegate()
        delegate.store = fixture.store
        let drafts = WebDraftStore(store: fixture.store)
        let controller = WebViewController(store: drafts)
        _ = controller.view
        let url = try XCTUnwrap(URL(string: "https://example.com/termination-save-throws"))
        controller.webView.loadHTMLString(
            "<html><body><p id='text'>original</p></body></html>",
            baseURL: url
        )
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "加载完成"),
            object: controller.statusLabel
        )
        wait(for: [loaded], timeout: 5)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'must stay dirty on quit'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        _ = try evaluateInDraftWorld(
            "Element.prototype.cloneNode = function() { throw new Error('injected termination save failure'); }; true;",
            in: controller
        )
        delegate.webViewController = controller
        var replies: [Bool] = []
        var alertCount = 0
        delegate.terminationReplyHandler = { replies.append($0) }
        delegate.alertPresenter = { alert in
            alertCount += 1
            XCTAssertEqual(alert.buttons.map(\.title), ["重试", "放弃未保存内容并退出"])
            XCTAssertTrue(controller.needsDraftFlush)
            return alertCount == 1 ? .alertFirstButtonReturn : .alertSecondButtonReturn
        }

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateLater)
        let outcomeDeadline = Date().addingTimeInterval(2)
        while replies.isEmpty,
              fixture.saver.snapshots.isEmpty,
              Date() < outcomeDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(alertCount, 2)
        XCTAssertEqual(replies, [true])
        XCTAssertTrue(fixture.saver.snapshots.isEmpty)
        XCTAssertTrue(controller.needsDraftFlush)
        XCTAssertNil(try drafts.draft(for: url))
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

    private func waitForDraft(
        containing text: String,
        for url: URL,
        in drafts: WebDraftStore,
        timeout: TimeInterval = 2
    ) throws -> WebDraft {
        let deadline = Date().addingTimeInterval(timeout)
        var matched: WebDraft?
        while matched == nil && Date() < deadline {
            if let draft = try drafts.draft(for: url), draft.sanitizedBodyHTML.contains(text) {
                matched = draft
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        return try XCTUnwrap(matched)
    }

    private func evaluateInDraftWorld(_ script: String, in controller: WebViewController) throws -> Any? {
        let completed = expectation(description: "isolated JavaScript evaluation completed")
        var result: Any?
        var evaluationError: Error?
        controller.webView.evaluateJavaScript(
            script,
            in: nil,
            in: .world(name: "FloatingWorkspace.WebDraft")
        ) { completion in
            switch completion {
            case .success(let value):
                result = value
            case .failure(let error):
                evaluationError = error
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        if let evaluationError {
            throw evaluationError
        }
        return result
    }

    private func evaluate(_ script: String, in controller: WebViewController) throws -> Any? {
        let completed = expectation(description: "JavaScript evaluation completed")
        var result: Any?
        var evaluationError: Error?
        controller.webView.evaluateJavaScript(script) { value, error in
            result = value
            evaluationError = error
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        if let evaluationError {
            throw evaluationError
        }
        return result
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
