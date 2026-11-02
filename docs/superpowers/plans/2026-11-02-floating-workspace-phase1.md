# Floating Workspace Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, editable macOS floating workspace with note and blank modes, global pin toggling, local persistence, and a menu-bar controller.

**Architecture:** A SwiftPM library owns the Codable model, asynchronous persistence, AppKit window/editor controllers, and Carbon hotkey. A small executable wires those controllers together; XCTest uses deterministic scheduler/saver doubles, while the final `.app` is verified against real windows.

**Tech Stack:** Swift 6.3.3, SwiftPM 5.9 manifest, AppKit, Carbon HIToolbox, Combine, Foundation JSON/FileManager, XCTest.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-11-02-floating-workspace-phase1-design.md`; Phase 1 implements note and blank modes only.
- Use public AppKit and Carbon only. No SkyLight, private APIs, SIP changes, injection, Accessibility or Screen Recording permission, third-party dependency, account, telemetry, or Phase 1 networking.
- Xcode 27.2 is installed at `/Applications/Xcode.app/Contents/Developer`. Prefix build/test commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because `xcode-select` still points to Command Line Tools; do not change the global selection.
- `NSPanel.isFloatingPanel = true`, `hidesOnDeactivate = false`; pinned level is `.floating`, unpinned level is `.normal`.
- Layout is the approved left rail with all four entries; image and web entries are visible but disabled in Phase 1. Do not create an image editor or WebView.
- Default window is `520 × 540` pt, minimum `360 × 320` pt, note font is 16 pt.
- Global hotkey is exactly `⌃⌥⌘P`; menu and hotkey operate on the same `FloatingWindowController` and `ContentStore` instances.
- Store only `workspace-v1.json` under Application Support `FloatingWorkspace/`; window frame is stored only through autosave name `FloatingWorkspaceFrame`.
- Saves are asynchronous, debounced by 300ms, and atomic. A newer edit during an in-flight save must trigger a subsequent save before dirty can clear.
- Corrupt JSON is moved to `workspace-v1.corrupt-<timestamp>.json` before defaults are used. Save failure retains content and dirty state.
- Termination flushes asynchronously. Failure pauses termination and offers retry or explicit discard; no false saved state.
- Local evidence belongs in `.artifacts/`; source, reusable tests, packaging, and documentation may be committed. Do not push or publish to GitHub without fresh user approval.
- Create a new feature worktree at execution time. Do not reuse the abandoned private-API worktree or its probe implementation.

---

## File Map

- `Package.swift`: `FloatingWorkspaceCore` library, `FloatingWorkspace` executable, XCTest target.
- `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`: content model, modes, load result, save state.
- `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`: synchronous atomic file persistence and corrupt-file recovery.
- `Sources/FloatingWorkspaceCore/ContentStore.swift`: published state, asynchronous debounce/save pipeline, flush.
- `Sources/FloatingWorkspaceCore/SaveScheduling.swift`: timer scheduler and background save worker contracts.
- `Sources/FloatingWorkspaceCore/FloatingWindowController.swift`: public AppKit panel, level/title/color/frame behavior.
- `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`: left rail, note editor, blank controls, save status.
- `Sources/FloatingWorkspaceCore/HotkeyController.swift`: Carbon registration and callback.
- `Sources/FloatingWorkspaceCore/MenuBarController.swift`: status item and shared actions.
- `Sources/FloatingWorkspace/main.swift`: application startup.
- `Sources/FloatingWorkspace/AppDelegate.swift`: wiring, store URL override, termination flush.
- `Tests/FloatingWorkspaceCoreTests/TestDoubles.swift`: fake loader, scheduler, saver, store factory.
- `Tests/FloatingWorkspaceCoreTests/WorkspaceFileStoreTests.swift`: model, atomic round-trip, corruption recovery.
- `Tests/FloatingWorkspaceCoreTests/ContentStoreTests.swift`: debounce, coalescing, failure, flush.
- `Tests/FloatingWorkspaceCoreTests/FloatingWindowControllerTests.swift`: real NSPanel configuration and state.
- `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`: enabled modes, editor/model binding, blank controls.
- `Resources/Info.plist`: accessory app metadata.
- `Scripts/build-app.sh`: release build and ad-hoc signed `.app`.
- `docs/testing/floating-workspace-phase1-acceptance.md`: reusable real acceptance steps.
- `README.md`, `LICENSE`: build/use/limits and MIT grant.

### Task 1: Model and Atomic File Persistence

**Files:**
- Create: `Package.swift`
- Modify: `.gitignore`
- Create: `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`
- Create: `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/WorkspaceFileStoreTests.swift`

**Interfaces:**
- Consumes: Foundation and the approved schema.
- Produces: `WorkspaceContent`, `WorkspaceMode`, `RGBAColor`, `WorkspaceLoadResult`, `WorkspacePersisting`, and `WorkspaceFileStore` for Task 2.

- [ ] **Step 1: Create the package and failing persistence tests**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingWorkspace",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FloatingWorkspaceCore", targets: ["FloatingWorkspaceCore"])
    ],
    targets: [
        .target(name: "FloatingWorkspaceCore", path: "Sources/FloatingWorkspaceCore"),
        .testTarget(
            name: "FloatingWorkspaceCoreTests",
            dependencies: ["FloatingWorkspaceCore"],
            path: "Tests/FloatingWorkspaceCoreTests"
        )
    ]
)
```

Append `.build/`, `.swiftpm/`, `.artifacts/`, `dist/`, and `.DS_Store` to `.gitignore`, preserving `.worktrees/` and `.superpowers/`.

Create `WorkspaceFileStoreTests.swift` with three tests:

```swift
import XCTest
@testable import FloatingWorkspaceCore

final class WorkspaceFileStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDefaultContentAndAtomicRoundTrip() throws {
        let file = try temporaryDirectory().appendingPathComponent("nested/workspace-v1.json")
        let store = WorkspaceFileStore(fileURL: file)
        let initial = try store.load()
        XCTAssertEqual(initial.content, .default)
        XCTAssertNil(initial.recoveryURL)

        var expected = WorkspaceContent.default
        expected.noteText = "浮窗正文"
        expected.selectedMode = .blank
        expected.blankTitle = "参考"
        expected.isPinned = false
        try store.save(expected)
        let loaded = try store.load()
        XCTAssertEqual(loaded.content, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptJSONIsMovedToTimestampedBackup() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let invalid = Data("not-json".utf8)
        try invalid.write(to: file)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = WorkspaceFileStore(fileURL: file, now: { fixedDate })

        let loaded = try store.load()
        XCTAssertEqual(loaded.content, .default)
        let backup = try XCTUnwrap(loaded.recoveryURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("workspace-v1.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: backup), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testImageAndWebAreNotEnabledInPhaseOne() {
        XCTAssertTrue(WorkspaceMode.note.isEnabledInPhase1)
        XCTAssertTrue(WorkspaceMode.blank.isEnabledInPhase1)
        XCTAssertFalse(WorkspaceMode.image.isEnabledInPhase1)
        XCTAssertFalse(WorkspaceMode.web.isEnabledInPhase1)
    }
}
```

Run `xcrun swift test --filter WorkspaceFileStoreTests`. Expected: FAIL because the model and file store do not exist.

- [ ] **Step 2: Implement the exact schema**

Create `WorkspaceModels.swift`:

```swift
import Foundation

public enum WorkspaceMode: String, Codable, Sendable, CaseIterable {
    case note, image, web, blank

    public var isEnabledInPhase1: Bool {
        self == .note || self == .blank
    }
}

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct WorkspaceContent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var selectedMode: WorkspaceMode
    public var noteText: String
    public var blankTitle: String
    public var blankBackground: RGBAColor
    public var isPinned: Bool

    public static let `default` = WorkspaceContent(
        schemaVersion: 1,
        selectedMode: .note,
        noteText: "",
        blankTitle: "空白窗口",
        blankBackground: RGBAColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        isPinned: true
    )
}

public struct WorkspaceLoadResult: Equatable, Sendable {
    public let content: WorkspaceContent
    public let recoveryURL: URL?
}

public enum SaveState: Equatable, Sendable {
    case saved
    case saving
    case failed(String)
}
```

- [ ] **Step 3: Implement atomic save and corrupt-file recovery**

Create `WorkspaceFileStore.swift` with this contract:

```swift
public protocol WorkspacePersisting {
    func load() throws -> WorkspaceLoadResult
    func save(_ content: WorkspaceContent) throws
}

public struct WorkspaceFileStore: WorkspacePersisting {
    public let fileURL: URL
    private let now: () -> Date

    public init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }
}
```

`load()` returns defaults when no file exists. It decodes JSON with `JSONDecoder`; on decoding failure, move the original to `workspace-v1.corrupt-<ISO8601 timestamp with colons replaced by dashes>.json`, then return defaults plus the backup URL. `save()` validates `schemaVersion == 1`, clamps color channels to the closed range from 0 through 1, creates the parent directory, encodes with `.prettyPrinted` and `.sortedKeys`, and writes with `Data.write(options: .atomic)`.

The corruption branch is:

```swift
let stamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
let backup = fileURL.deletingLastPathComponent()
    .appendingPathComponent("workspace-v1.corrupt-\(stamp).json")
try FileManager.default.moveItem(at: fileURL, to: backup)
return WorkspaceLoadResult(content: .default, recoveryURL: backup)
```

- [ ] **Step 4: Run green tests and commit**

```bash
xcrun swift test --filter WorkspaceFileStoreTests
git add Package.swift .gitignore Sources/FloatingWorkspaceCore Tests/FloatingWorkspaceCoreTests
git diff --cached --check
git commit -m "feat: add atomic workspace persistence" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: three tests PASS, including the exact corrupt-file bytes preserved in the backup.

### Task 2: Asynchronous Debounced ContentStore

**Files:**
- Create: `Sources/FloatingWorkspaceCore/SaveScheduling.swift`
- Create: `Sources/FloatingWorkspaceCore/ContentStore.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/TestDoubles.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/ContentStoreTests.swift`

**Interfaces:**
- Consumes: `WorkspacePersisting`, `WorkspaceFileStore`, and `WorkspaceContent` from Task 1.
- Produces: `ContentStore`, `SaveScheduling`, `WorkspaceSaving`, and `WorkspaceSaveWorker` used by all UI and termination tasks.

- [ ] **Step 1: Write failing scheduler and in-flight edit tests**

Create `TestDoubles.swift` with a fake loader, a manually fired scheduler, and a saver whose completions are controlled by the test. The fake saver records snapshots and completions rather than calling `FileManager`.

Create `ContentStoreTests.swift` with these four behaviors:

```swift
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
```

Use a `drainMainQueue()` helper that spins `RunLoop.current` for 0.01 seconds so the saver's `Task { @MainActor in self?.finishSave(result, savedRevision: saveRevision) }` can finish. Run `xcrun swift test --filter ContentStoreTests`; expected FAIL because the scheduler and store are missing.

- [ ] **Step 2: Define scheduler and background saver contracts**

Create `SaveScheduling.swift`:

```swift
import Foundation

@MainActor
public protocol SaveScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

@MainActor
public final class TimerSaveScheduler: SaveScheduling {
    private var timer: Timer?
    public init() {}
    public func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in action() }
    }
    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

public protocol WorkspaceSaving {
    func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void)
}

public final class WorkspaceSaveWorker: WorkspaceSaving {
    private let store: WorkspaceFileStore
    private let queue = DispatchQueue(label: "local.floatingworkspace.save", qos: .utility)

    public init(store: WorkspaceFileStore) { self.store = store }

    public func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            completion(Result { try self.store.save(content) })
        }
    }
}
```

- [ ] **Step 3: Implement ContentStore without blocking editing**

Create `ContentStore.swift` with `import Combine` as `@MainActor public final class ContentStore: ObservableObject` with:

```swift
@Published public private(set) var content: WorkspaceContent
@Published public private(set) var saveState: SaveState = .saved
public private(set) var isDirty = false
public private(set) var isSaving = false
public let recoveryURL: URL?

public convenience init(fileURL: URL) throws {
    let files = WorkspaceFileStore(fileURL: fileURL)
    try self.init(
        loader: files,
        scheduler: TimerSaveScheduler(),
        saver: WorkspaceSaveWorker(store: files)
    )
}
```

The designated initializer is `public init(loader: any WorkspacePersisting, scheduler: any SaveScheduling, saver: any WorkspaceSaving) throws`. Public mutation and flush signatures are `public func update(_ mutation: (inout WorkspaceContent) -> Void)` and `public func flush(completion: ((Result<Void, Error>) -> Void)? = nil)`. `update` increments a revision, mutates content, marks dirty/saving, and schedules 0.3 seconds. `flush` cancels the timer, appends an optional completion and returns immediately while a save is in flight, captures the current revision/snapshot, sets `isSaving = true`, and calls the background saver. `finishSave` sets `isSaving = false` before applying its result; a changed-revision success immediately starts the next save and sets it back to true.

The completion rule is exact:

- Success with unchanged revision: clear dirty, set `.saved`, and complete all pending flush completions with success.
- Success with changed revision: keep dirty and pending completions, then immediately flush the newer snapshot.
- Failure: keep dirty/content, set `.failed(error.localizedDescription)`, and complete all pending flush completions with failure.
- Clean flush: complete success immediately without calling the saver.

Every saver callback returns to the main actor with `Task { @MainActor in self?.finishSave(result, savedRevision: saveRevision) }`; `finishSave` applies the completion rules above.

- [ ] **Step 4: Run both persistence suites and commit**

```bash
xcrun swift test --filter WorkspaceFileStoreTests
xcrun swift test --filter ContentStoreTests
git add Sources/FloatingWorkspaceCore Tests/FloatingWorkspaceCoreTests
git diff --cached --check
git commit -m "feat: add nonblocking workspace autosave" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: all persistence and ContentStore tests PASS; the in-flight test proves the second snapshot is required before dirty clears.

### Task 3: Public AppKit Floating Window

**Files:**
- Create: `Sources/FloatingWorkspaceCore/FloatingWindowController.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/FloatingWindowControllerTests.swift`

**Interfaces:**
- Consumes: `ContentStore` and its `@Published` content.
- Produces: `FloatingWindowController`, `togglePinned()`, `setPinned(_:)`, `show()`, `hide()`, and `setBlankSize(width:height:)`.

- [ ] **Step 1: Write failing real-NSPanel tests**

Create main-actor tests that instantiate `ContentStoreTestDoubles` and `FloatingWindowController`. Call `_ = NSApplication.shared` in `setUp()` before creating any panel. Assert:

```swift
XCTAssertTrue(controller.panel.isFloatingPanel)
XCTAssertFalse(controller.panel.hidesOnDeactivate)
XCTAssertEqual(controller.panel.frameAutosaveName, "FloatingWorkspaceFrame")
XCTAssertEqual(controller.panel.minSize, NSSize(width: 360, height: 320))
XCTAssertEqual(controller.panel.level, .floating)

controller.setPinned(false)
XCTAssertEqual(controller.panel.level, .normal)
XCTAssertFalse(doubles.store.content.isPinned)
controller.togglePinned()
XCTAssertEqual(controller.panel.level, .floating)

doubles.store.update {
    $0.selectedMode = .blank
    $0.blankTitle = "自定义标题"
    $0.blankBackground = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
}
XCTAssertEqual(controller.panel.title, "自定义标题")
XCTAssertEqual(controller.panel.backgroundColor, NSColor(red: 1, green: 0, blue: 0, alpha: 1))

controller.setBlankSize(width: 100, height: 900)
XCTAssertEqual(controller.panel.frame.size, NSSize(width: 360, height: 900))
```

Run `xcrun swift test --filter FloatingWindowControllerTests`; expected FAIL because the controller is missing.

- [ ] **Step 2: Implement FloatingWindowController**

Create `@MainActor public final class FloatingWindowController: NSObject` with `public let panel: NSPanel`, a Combine subscription to `store.$content`, and these methods:

```swift
public func setPinned(_ pinned: Bool) {
    store.update { $0.isPinned = pinned }
}

public func togglePinned() {
    setPinned(!store.content.isPinned)
}

public func show() { panel.makeKeyAndOrderFront(nil) }
public func hide() { panel.orderOut(nil) }

public func setBlankSize(width: Double, height: Double) {
    let size = NSSize(width: max(360, width), height: max(320, height))
    panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
}
```

Build the panel with titled/closable/miniaturizable/resizable styles, default `520 × 540`, minimum `360 × 320`, 16 pt-compatible content sizing, `isFloatingPanel = true`, `hidesOnDeactivate = false`, and frame autosave name `FloatingWorkspaceFrame`. Apply content by setting `.floating`/`.normal`, note title `悬浮工作台`, blank title with empty-title fallback to `悬浮工作台`, and blank sRGB background. Note mode uses `.windowBackgroundColor`.

- [ ] **Step 3: Run window and persistence tests, then commit**

```bash
xcrun swift test --filter FloatingWindowControllerTests
xcrun swift test
git add Sources/FloatingWorkspaceCore/FloatingWindowController.swift Tests/FloatingWorkspaceCoreTests/FloatingWindowControllerTests.swift
git diff --cached --check
git commit -m "feat: add editable floating workspace window" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: real NSPanel tests PASS with no private API and no permissions prompt.

### Task 4: Left Rail, Note Editor, and Blank Controls

**Files:**
- Create: `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`
- Modify: `Sources/FloatingWorkspaceCore/FloatingWindowController.swift`

**Interfaces:**
- Consumes: `ContentStore` and `FloatingWindowController` from Tasks 2–3.
- Produces: `WorkspaceViewController` and its `view` installed as the panel content in this task.

- [ ] **Step 1: Write failing mode and editor-binding tests**

Create main-actor tests that call `_ = NSApplication.shared` in `setUp()` and then load `WorkspaceViewController.view`. Assert:

- `noteButton` and `blankButton` are enabled; `imageButton` and `webButton` are disabled.
- Calling `selectMode(.image)` leaves `store.content.selectedMode` unchanged.
- Calling `selectMode(.blank)` updates the model and visible editor container.
- Setting `noteTextView.string` to `编辑内容` and invoking `textDidChange` updates `store.content.noteText`.
- Changing `blankTitleField` updates the model and panel title.
- Changing `colorWell.color` updates `blankBackground` within 0.001 per channel.
- Setting width/height fields to `640` and `700` and invoking `blankSizeChanged()` sets the real panel size.
- `$saveState` maps `.saved` to `已保存`, `.saving` to `保存中`, and `.failed` to `保存失败` in `saveStateLabel`.

Run `xcrun swift test --filter WorkspaceViewControllerTests`; expected FAIL because the view controller and controls are missing.

- [ ] **Step 2: Implement the approved left-rail workspace**

Create `@MainActor public final class WorkspaceViewController: NSViewController, NSTextViewDelegate` with internal test-visible controls:

```swift
let noteButton = NSButton()
let imageButton = NSButton()
let webButton = NSButton()
let blankButton = NSButton()
let noteTextView = NSTextView()
let blankTitleField = NSTextField()
let colorWell = NSColorWell()
let widthField = NSTextField()
let heightField = NSTextField()
let saveStateLabel = NSTextField(labelWithString: "")
```

Build a 76 pt left rail, a mode container, and a bottom status bar. Set accessibility identifiers `mode-note`, `mode-image`, `mode-web`, `mode-blank`, `note-editor`, `blank-title`, `blank-color`, `blank-width`, `blank-height`, and `save-state`. Use the four bordered `NSButton` instances declared above; do not shrink controls below the approved readable sizing.

`selectMode(_ mode: WorkspaceMode)` guards `mode.isEnabledInPhase1`, then updates `selectedMode`. The note editor uses 16 pt plain text and writes `textDidChange` into the model. Blank controls write title/color to the model and call `setBlankSize` for width/height. Combine subscriptions update controls and save status without creating WebKit or image-editing objects.

- [ ] **Step 3: Install the workspace view and run tests**

In `FloatingWindowController`, install `WorkspaceViewController` after both controllers exist without introducing a retain cycle. A valid ownership rule is: `FloatingWindowController` strongly owns the view controller; the view controller holds the window controller weakly.

Run:

```bash
xcrun swift test --filter WorkspaceViewControllerTests
xcrun swift test
git add Sources/FloatingWorkspaceCore Tests/FloatingWorkspaceCoreTests
git diff --cached --check
git commit -m "feat: add note and blank workspace modes" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: all view-binding and previous tests PASS; image/web remain disabled.

### Task 5: Menu Bar, Global Hotkey, and Safe Termination

**Files:**
- Create: `Sources/FloatingWorkspaceCore/HotkeyController.swift`
- Create: `Sources/FloatingWorkspaceCore/MenuBarController.swift`
- Create: `Sources/FloatingWorkspace/main.swift`
- Create: `Sources/FloatingWorkspace/AppDelegate.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: one shared `ContentStore` and `FloatingWindowController` per app instance.
- Produces: runnable accessory app, menu actions, `⌃⌥⌘P`, and asynchronous termination flush.

- [ ] **Step 1: Add the executable target and Carbon hotkey**

Add executable product/target `FloatingWorkspace`, depending on `FloatingWorkspaceCore`, at `Sources/FloatingWorkspace`.

Implement `@MainActor public final class HotkeyController` with `public init(action: @escaping () -> Void)`, `start() throws`, and `stop()`. Register `kVK_ANSI_P` with `controlKey | optionKey | cmdKey`, signature `0x46575031`, ID `1`, on `GetApplicationEventTarget()`.

```swift
let status = RegisterEventHotKey(
    UInt32(kVK_ANSI_P),
    UInt32(controlKey | optionKey | cmdKey),
    EventHotKeyID(signature: 0x46575031, id: 1),
    GetApplicationEventTarget(),
    0,
    &hotKeyRef
)
guard status == noErr else {
    throw HotkeyError.registrationFailed(status)
}
```

The event callback dispatches the controller action to the main actor. `stop()` unregisters both hotkey and handler. `HotkeyError.registrationFailed` includes the numeric OSStatus in `localizedDescription`.

- [ ] **Step 2: Implement shared menu actions and app wiring**

`MenuBarController` creates a status item and exactly these actions: `显示／隐藏浮窗`, `切换置顶`, and `退出悬浮工作台`. Show/hide uses the current panel visibility; toggle calls the same `FloatingWindowController.togglePinned()` used by the hotkey.

Create `main.swift`:

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
```

`AppDelegate` constructs one file store, `ContentStore`, `FloatingWindowController`, `WorkspaceViewController`, `MenuBarController`, and `HotkeyController`. Resolve the default JSON URL under Application Support `FloatingWorkspace/workspace-v1.json`. For isolated acceptance only, allow `FLOATING_WORKSPACE_STORE_URL` to override that full file URL. A load failure other than corrupt-JSON recovery shows an alert and does not silently overwrite data.

- [ ] **Step 3: Implement asynchronous termination flush**

Use this exact lifecycle:

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !store.isDirty && !store.isSaving else {
        store.flush { result in
            switch result {
            case .success:
                NSApp.reply(toApplicationShouldTerminate: true)
            case .failure:
                presentTerminationSaveFailure()
            }
        }
        return .terminateLater
    }
    return .terminateNow
}
```

`presentTerminationSaveFailure` offers `重试` and `放弃未保存内容并退出`; retry calls flush again, discard replies `true`. `applicationWillTerminate` stops the hotkey. Never mark dirty false merely because termination was requested.

- [ ] **Step 4: Run real app checks**

```bash
xcrun swift build --product FloatingWorkspace
.build/debug/FloatingWorkspace
```

Verify note editing, blank controls, hide/show, and `⌃⌥⌘P` against Safari, Notes, and the installed IDE. Keep one instance running and launch a second to force hotkey conflict; the second shows a numeric error and its menu still works. Use a temporary `FLOATING_WORKSPACE_STORE_URL` to verify corrupt-file recovery and a path under `/dev/null/` to verify save failure and retry/discard termination without touching real content.

- [ ] **Step 5: Run all tests and commit**

```bash
xcrun swift test
git add Package.swift Sources Tests
git diff --cached --check
git commit -m "feat: add menu controls and safe app lifecycle" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: full suite PASS; real hotkey conflict and save-failure paths are visibly reported.

### Task 6: Package, Document, and Accept Phase 1

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `docs/testing/floating-workspace-phase1-acceptance.md`
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: all Phase 1 code and tests.
- Produces: `dist/FloatingWorkspace.app`, reusable acceptance instructions, and MIT source ready for local review.

- [ ] **Step 1: Add bundle metadata and build script**

Use bundle ID `local.floatingworkspace`, executable `FloatingWorkspace`, display name `悬浮工作台`, version `1.0.0 (1)`, minimum macOS `13.0`, and `LSUIElement = true`. Add no Accessibility or Screen Recording usage keys.

Create `Scripts/build-app.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
xcrun swift build -c release --product FloatingWorkspace
APP="$ROOT/dist/FloatingWorkspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/FloatingWorkspace" "$APP/Contents/MacOS/FloatingWorkspace"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/FloatingWorkspace"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
```

Run `chmod +x Scripts/build-app.sh && Scripts/build-app.sh && codesign --verify --verbose=2 dist/FloatingWorkspace.app`. Expected: signed app verifies successfully.

- [ ] **Step 2: Write the exact acceptance procedure**

Create `docs/testing/floating-workspace-phase1-acceptance.md` covering all eight spec groups:

1. Note edit remains visible above Safari, Notes, and IDE after focus changes; no focus stealing.
2. Hotkey and menu both toggle `.floating`/`.normal` on the same panel.
3. Blank title/background/width/height apply immediately and survive relaunch.
4. Note, selected mode, frame, and pin state survive relaunch.
5. Hide/show works from the menu bar with no Dock icon.
6. A second app instance produces a numeric hotkey conflict while menu actions remain usable.
7. `FLOATING_WORKSPACE_STORE_URL=/dev/null/workspace-v1.json` produces visible save failure; retry and explicit discard termination behave as designed.
8. An isolated invalid JSON file is moved to a timestamped backup; app starts with defaults and shows recovery information.

Throughout all eight groups, verify that no Accessibility or Screen Recording prompt appears and that Phase 1 makes no network request.

Record dated output and screenshots only in `.artifacts/acceptance/`; do not commit them.

- [ ] **Step 3: Add README and MIT license**

README includes the four-mode roadmap but labels only note/blank as Phase 1 complete. Document `⌃⌥⌘P`, menu actions, local JSON path, frame autosave, save-failure behavior, corrupt backups, no special permissions, no SkyLight, and no Phase 1 networking. Build commands:

```bash
xcrun swift test
Scripts/build-app.sh
open dist/FloatingWorkspace.app
```

Include the isolated test URL environment variable only in the testing section. Add the complete MIT License with `Copyright (c) 2026 Yintong`; GitHub publication and copyright-line review remain separate user-approved actions.

- [ ] **Step 4: Run automated and real acceptance**

```bash
xcrun swift test
xcrun swift build -c release --product FloatingWorkspace
Scripts/build-app.sh
codesign --verify --verbose=2 dist/FloatingWorkspace.app
git diff --check
open dist/FloatingWorkspace.app
```

Execute every acceptance group. Any failure blocks a completion claim; fix through a reviewed change and rerun affected tests.

- [ ] **Step 5: Review and commit without publishing**

```bash
git status --short
git add Resources Scripts docs/testing README.md LICENSE
git diff --cached --check
git diff --cached --stat
git commit -m "docs: package and accept floating workspace phase one" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
git status --short
```

Expected: only source, tests, packaging, and documentation are committed; `.artifacts/`, `.build/`, `dist/`, `.worktrees/`, and `.superpowers/` remain excluded. Do not add a remote or push.

---

## Completion Gate

Phase 1 is complete only when all automated tests and all eight real acceptance groups pass on the current Mac. Image editing, web body editing, and web-edit replay remain separate phases and must not be included in the Phase 1 completion claim.
