# Floating Workspace Web Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native WKWebView web mode with navigation, local body editing, sanitized per-URL drafts, and one-shot replay while preserving all existing workspace behavior.

**Architecture:** A schema-v2 model and migration layer stores sanitized drafts. `WebViewController` owns WebKit navigation/editing, a DOM-based sanitizer and draft store own safe persistence/replay, and the existing workspace/menu/theme controllers integrate the new mode without changing note/blank behavior.

**Tech Stack:** Swift 6.3.3, SwiftPM, AppKit, WebKit, Combine, Foundation, XCTest, Xcode 27.2.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-11-09-floating-workspace-web-design.md`; no CEF, Chromium, Electron, third-party browser, remote writes, or image-mode work.
- Only `http`/`https` URLs. Reject credentials in URLs and reject invalid schemes before creating a request.
- Use `WKWebsiteDataStore.nonPersistent()`; never persist cookies, passwords, or form values. Do not bypass certificate validation.
- Editing is local `body.contentEditable`; form submit is intercepted. No remote write API or browser injection.
- Sanitize at save and replay: remove script/iframe/object/embed/meta refresh, all `on*` attributes, `javascript:` URLs, form input values, and form action/method.
- Normalize URL with lowercase scheme/host, no fragment/user/password/default ports, empty path `/`, preserve other path/query/trailing slash.
- Replay once per main-frame load after `didFinish`; never loop or fight dynamic updates. Failure preserves draft and shows `无法应用上次修改`.
- DOM autosave is asynchronous after 800ms idle, not on the existing 300ms note cadence. End-edit/navigation/termination must flush the current draft first.
- Preserve note/blank content, schema-v1 bytes until first real save, atomic writes, glass themes, hotkeys, frame restore, and all existing tests/acceptance.
- Build/test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; local evidence only under `.artifacts/`; no push or publication.

---

## File Map

- `Sources/FloatingWorkspaceCore/WebDraft.swift`: draft model and URL normalization.
- `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`: schema v2 and webDrafts.
- `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`: v1→v2 migration and backup.
- `Sources/FloatingWorkspaceCore/WebDraftStore.swift`: typed draft lookup/update through ContentStore.
- `Sources/FloatingWorkspaceCore/WebViewController.swift`: WebKit toolbar/navigation/edit/replay.
- `Sources/FloatingWorkspaceCore/WebDraftSanitizer.swift`: DOM sanitizer/editing JavaScript.
- `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`: web container and mode integration.
- `Sources/FloatingWorkspace/AppDelegate.swift`: async draft flush before termination flush.
- `Tests/FloatingWorkspaceCoreTests/WebDraftTests.swift`: URL and migration tests.
- `Tests/FloatingWorkspaceCoreTests/WebViewControllerTests.swift`: WebKit loading, editing, sanitizing, replay, flush.
- Existing model/controller tests: backward compatibility and mode/theme behavior.
- `Tests/Fixtures/web/`: local static and dynamic HTML for acceptance.
- `README.md` and `docs/testing/floating-workspace-phase1-acceptance.md`: web usage and final verification.

### Task 1: Schema V2, Migration, and Draft Identity

**Files:**
- Create: `Sources/FloatingWorkspaceCore/WebDraft.swift`
- Create: `Sources/FloatingWorkspaceCore/WebDraftStore.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/WebDraftTests.swift`

**Interfaces:**
- Consumes: existing schema v1 and atomic store.
- Produces: `WebDraft`, `WebDraftKey.normalized`, `WebDraftStore`, and `WorkspaceLoadResult.migrationBackupURL` for Task 3.

- [ ] **Step 1: Write failing migration and URL tests**

Cover these exact behaviors:

```swift
func testV1MigrationPreservesContentAndCreatesBackupBeforeNextSave() throws {
    let file = temporaryFile()
    let original = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
    try original.write(to: file)
    let store = WorkspaceFileStore(fileURL: file)
    let result = try store.load()
    XCTAssertEqual(result.content.schemaVersion, 2)
    XCTAssertEqual(result.content.noteText, "keep")
    XCTAssertEqual(result.content.selectedMode, .blank)
    XCTAssertFalse(result.content.isPinned)
    XCTAssertTrue(result.content.webDrafts.isEmpty)
    XCTAssertEqual(try Data(contentsOf: file), original)
    let backup = try XCTUnwrap(result.migrationBackupURL)
    XCTAssertEqual(try Data(contentsOf: backup), original)
}

func testURLNormalizationAndCredentialRejection() throws {
    XCTAssertEqual(try WebDraftKey.normalized(URL(string: "HTTPS://Example.COM:443/a?b=1#frag")!), "https://example.com/a?b=1")
    XCTAssertEqual(try WebDraftKey.normalized(URL(string: "http://example.com:80")!), "http://example.com/")
    XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "https://user:secret@example.com/private")!))
    XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "file:///tmp/private.html")!))
}
```

Add a version-3 rejection test proving unsupported data does not silently reset. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter WebDraftTests`; expected missing-type failures.

- [ ] **Step 2: Implement draft identity and schema-v2 model**

Create:

```swift
public struct WebDraft: Codable, Equatable, Sendable {
    public let url: String
    public let sanitizedBodyHTML: String
    public let updatedAt: Date
}

public enum WebDraftKey {
    public static func normalized(_ url: URL) throws -> String
}
```

Reject non-http(s), user/password, and malformed hosts. Use URLComponents normalization exactly as specified.

Extend `WorkspaceContent` with `webDrafts: [String: WebDraft]`, default schema 2, and custom decoding that supplies an empty dictionary when absent. Extend `WorkspaceLoadResult` with `migrationBackupURL: URL?`, defaulting to nil in its memberwise initializer so existing call sites remain valid.

- [ ] **Step 3: Implement v1 migration and typed draft store**

`WorkspaceFileStore.load` accepts v1 and v2. For v1, copy the original bytes to a collision-safe `workspace-v1.backup-<timestamp>.json`, return migrated v2 content plus backup URL, and leave original bytes untouched until the next real save. `save` accepts only schema 2 and continues atomic writes. Unsupported versions use the existing corrupt/incompatible path.

`WebDraftStore` is a small `@MainActor` wrapper with:

```swift
func draft(for url: URL) throws -> WebDraft?
func saveDraft(_ draft: WebDraft) throws
```

It normalizes the URL, reads/writes `ContentStore.content.webDrafts`, and uses `ContentStore.update` so save/dirty/termination behavior remains shared.

- [ ] **Step 4: Run migration/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter WebDraftTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/WebDraft.swift Sources/FloatingWorkspaceCore/WebDraftStore.swift Sources/FloatingWorkspaceCore/WorkspaceModels.swift Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift Tests/FloatingWorkspaceCoreTests/WebDraftTests.swift
git commit -m "feat: migrate workspace schema for web drafts" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: migration/URL tests and all previous tests PASS; original v1 bytes and backup are byte-identical.

### Task 2: Native WebKit Browser Shell

**Files:**
- Create: `Sources/FloatingWorkspaceCore/WebViewController.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/WebViewControllerTests.swift`

**Interfaces:**
- Consumes: public WebKit and the existing AppKit view structure.
- Produces: `WebViewController`, `load(url:)`, `openURLFromField()`, `toggleEditing()`, and `flushDraft(completion:)` used by Tasks 3–4.

- [ ] **Step 1: Write failing browser configuration and editing tests**

Instantiate the controller and assert `webView.configuration.websiteDataStore.isPersistent == false`. Use `loadHTMLString` on a tiny HTML fixture and a navigation expectation to prove editing toggles:

```swift
func testEditingToggleUsesLocalContentEditable() throws {
    let controller = WebViewController(store: makeStore())
    controller.loadHTMLForTesting("<html><body><p>hello</p></body></html>")
    waitForNavigation()
    controller.toggleEditing()
    XCTAssertEqual(try evaluateBodyContentEditable(), "true")
    controller.toggleEditing()
    XCTAssertEqual(try evaluateBodyContentEditable(), "false")
}

func testInvalidURLDoesNotCreateRequest() {
    let controller = WebViewController(store: makeStore())
    controller.urlField.stringValue = "file:///tmp/private.html"
    controller.openURLFromField()
    XCTAssertNil(controller.webView.url)
    XCTAssertEqual(controller.errorLabel.stringValue, "仅支持 http 和 https 链接")
}
```

Add credential rejection and no-body error tests. Run focused tests; expected missing controller failures.

- [ ] **Step 2: Implement the browser and toolbar**

`WebViewController` owns `webView`, `urlField`, open/back/forward/refresh/edit buttons, and status/error labels. Configure `WKWebViewConfiguration` with `WKWebsiteDataStore.nonPersistent()` and standard WebKit defaults. `load(url:)` accepts only http/https and rejects credentials. `openURLFromField()` validates before creating `URLRequest`.

`toggleEditing()` sets `document.body.contentEditable` and intercepts form submit without changing remote state. `flushDraft(completion:)` is a no-op stub in this task that calls completion immediately, to be implemented by Task 3.

- [ ] **Step 3: Add navigation and visible errors**

Implement `WKNavigationDelegate` for load completion/failure, invalid navigation, and certificate errors. Preserve current content on failure and show readable errors. Links opening a new window are loaded in the same web view rather than creating another app window. Navigation to another URL in Task 3 will first flush the current draft.

- [ ] **Step 4: Run focused/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter WebViewControllerTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/WebViewController.swift Tests/FloatingWorkspaceCoreTests/WebViewControllerTests.swift
git commit -m "feat: add native WebKit browser shell" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: WebKit configuration/editing/errors and all previous tests PASS.

### Task 3: Sanitized Drafts, Idle Save, and One-Shot Replay

**Files:**
- Create: `Sources/FloatingWorkspaceCore/WebDraftSanitizer.swift`
- Modify: `Sources/FloatingWorkspaceCore/WebViewController.swift`
- Modify: `Sources/FloatingWorkspace/AppDelegate.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/WebViewControllerTests.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/AppDelegateTests.swift`

**Interfaces:**
- Consumes: `WebDraftStore` and the Task 2 browser shell.
- Produces: complete draft save/replay and termination flushing.

- [ ] **Step 1: Write failing sanitizer and replay tests**

Fixture body includes text, a script, `onclick`, `javascript:` link, iframe, object, embed, meta refresh, a password input with a value, and a form with action/method. Saving must preserve ordinary text but remove every active element/attribute/value.

Add tests proving:
- Editing pauses serialize only after 800ms, not immediately or at 300ms.
- `didFinish` applies a saved draft once and reports `已恢复上次修改`.
- A replay JavaScript error reports `无法应用上次修改` and leaves the draft unchanged.
- Navigation and termination flush the current draft before `ContentStore.flush` and before the new URL loads.

- [ ] **Step 2: Implement DOM sanitizer and mutation idle path**

Create `WebDraftSanitizer.swift` with JavaScript source for:
- `setEditing(enabled)`: contentEditable, submit interception, and mutation observation.
- `sanitizeBody()`: clone body, remove the specified active elements/attributes/form state, and return sanitized HTML.
- `applySanitizedBody(html)`: sanitize the supplied HTML again and replace body content once.

Observe `MutationObserver` on body and report changes only after 800ms idle through a named `WKScriptMessageHandler`. Reset the timer on each mutation. No continuous DOM serialization loop.

- [ ] **Step 3: Implement save, replay, and flush**

On idle/edit-end, call `WebDraftStore.saveDraft` with the sanitized body, normalized URL, and current date. Save the current draft before navigation and termination. On `didFinish`, look up the current normalized URL and call `applySanitizedBody` once. Reset replay state on `didStartProvisionalNavigation`; never reapply due to subsequent DOM changes.

`flushDraft(completion:)` performs current DOM serialization when web mode is active and dirty, then completes. AppDelegate performs this async flush before calling the existing ContentStore termination flush. Failure preserves dirty state and follows the existing retry/discard alert.

- [ ] **Step 4: Run focused/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'WebViewControllerTests|AppDelegateTests'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/WebDraftSanitizer.swift Sources/FloatingWorkspaceCore/WebViewController.swift Sources/FloatingWorkspace/AppDelegate.swift Tests/FloatingWorkspaceCoreTests/WebViewControllerTests.swift Tests/FloatingWorkspaceCoreTests/AppDelegateTests.swift
git commit -m "feat: add safe web draft save and replay" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: sanitizer/replay/flush tests and all previous tests PASS.

### Task 4: Workspace Integration and Full Acceptance

**Files:**
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`
- Create: `Tests/Fixtures/web/static.html`
- Create: `Tests/Fixtures/web/dynamic.html`
- Modify: `README.md`
- Modify: `docs/testing/floating-workspace-phase1-acceptance.md`

**Interfaces:**
- Consumes: complete browser/draft implementation.
- Produces: enabled web mode, documentation, and final signed-app acceptance.

- [ ] **Step 1: Enable only web mode in the workspace**

Set `WorkspaceMode.web.isEnabledInPhase1 = true` while image remains disabled. Add a web container/controller to `WorkspaceViewController`, with cheap idempotent web button state and visibility updates on every emission. Keep the existing no-restyle-per-keystroke guard and theme update behavior. Update tests so web is selectable and image remains disabled.

- [ ] **Step 2: Add local acceptance fixtures and docs**

`static.html` contains editable text, navigation link, and the active-content fixture. `dynamic.html` changes body structure after load so replay must show `无法应用上次修改`. README documents navigation, editing, URL-based drafts, single replay, nonpersistent session data, privacy limits, and remote-write exclusion. Acceptance docs include all original eight groups plus web-specific checks and visual themes.

- [ ] **Step 3: Run automated and signed-app acceptance**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
codesign --verify --verbose=2 dist/FloatingWorkspace.app
git diff --check
```

Serve `Tests/Fixtures/web` on `127.0.0.1` without exposing it externally. On the final signed app, verify navigation, edit/refresh/replay, dynamic failure, navigation-before-save, sanitizer output, nonpersistent session, light/dark/accessibility appearance, and all eight original groups. No failed group may be masked by another passing check.

- [ ] **Step 4: Commit and perform whole-branch review**

```bash
git add Sources Tests README.md docs/testing/floating-workspace-phase1-acceptance.md
git commit -m "feat: enable WKWebView workspace mode" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Generate the full diff and dispatch the most capable available reviewer. Address Critical/Important findings through one reviewed fix wave. Local completion does not authorize push or publication.

---

## Completion Gate

Completion requires migration and sanitizer correctness, all automated tests, signed-package web edit/replay/error evidence, and all eight original acceptance groups. Image mode, persistent login state, Chromium, and remote website writes remain outside this completion claim.
