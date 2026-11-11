# Floating Workspace Edit Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add standard macOS edit menu actions and shortcuts for copy, paste, cut, select all, undo, and redo without changing existing editor or persistence behavior.

**Architecture:** A small `EditMenuController` builds the standard Edit menu using AppKit selectors. Targets remain nil so `NSApp.sendAction` follows the responder chain to the active `NSTextView`, `NSTextField`, or `WKWebView`.

**Tech Stack:** Swift 6.3.3, SwiftPM, AppKit, XCTest.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-11-11-floating-workspace-edit-shortcuts-design.md`.
- Required shortcuts: `⌘C`, `⌘V`, `⌘X`, `⌘A`, `⌘Z`, `⌘⇧Z`.
- Use standard selectors `copy:`, `paste:`, `cut:`, `selectAll:`, `undo:`, `redo:` with nil targets; no custom clipboard storage or key event interception.
- Do not change `⌃⌥⌘P`, content models, save/replay, image editing, or existing hotkeys.
- Build/test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no push or publication yet.

---

### Task 1: Standard Edit Menu and Responder-Chain Actions

**Files:**
- Create: `Sources/FloatingWorkspaceCore/EditMenuController.swift`
- Modify: `Sources/FloatingWorkspace/AppDelegate.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/EditMenuControllerTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: AppKit menu/responder chain and existing controllers.
- Produces: `EditMenuController.install(on:)` and real copy/paste/cut/selectAll/undo/redo behavior.

- [ ] **Step 1: Write failing menu-mapping and real-editor tests**

Create `EditMenuControllerTests.swift` with:

```swift
@MainActor
final class EditMenuControllerTests: XCTestCase {
    func testMenuUsesStandardSelectorsAndShortcuts() {
        let menu = EditMenuController.makeMenu()
        let actions = menu.items.map(\ .title)
        XCTAssertEqual(actions, ["复制", "粘贴", "剪切", "全选", "撤销", "重做"])
        let selectors = menu.items.map(\ .action)
        XCTAssertEqual(selectors, [
            #selector(copy:), #selector(paste:), #selector(cut:),
            #selector(selectAll:), #selector(undo:), #selector(redo:)
        ])
        for item in menu.items { XCTAssertNil(item.target) }
        XCTAssertEqual(menu.items.map(\ .keyEquivalent), ["c", "v", "x", "a", "z", "Z"])
        XCTAssertEqual(menu.items.last?.keyEquivalentModifierMask, .shift)
    }

    func testRealTextViewCopyPasteCutAndUndoRedo() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(text)
        window.makeFirstResponder(text)
        text.string = "hello"
        text.selectAll(nil)
        NSApp.sendAction(#selector(copy:), to: nil, from: nil)
        text.string = ""
        NSApp.sendAction(#selector(paste:), to: nil, from: nil)
        XCTAssertEqual(text.string, "hello")
        NSApp.sendAction(#selector(cut:), to: nil, from: nil)
        XCTAssertEqual(text.string, "")
        NSApp.sendAction(#selector(undo:), to: nil, from: nil)
        XCTAssertEqual(text.string, "hello")
        NSApp.sendAction(#selector(redo:), to: nil, from: nil)
        XCTAssertEqual(text.string, "")
    }
}
```

The second test must create a real first responder and use `NSApp.sendAction`, not direct model assignment between expected operations.

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter EditMenuControllerTests`. Expected: missing `EditMenuController` failure.

- [ ] **Step 2: Implement the standard menu controller**

Create `EditMenuController` with:

```swift
@MainActor
public enum EditMenuController {
    public static func makeMenu() -> NSMenu
    public static func install(on application: NSApplication)
}
```

Build one `编辑` submenu with `复制`, `粘贴`, `剪切`, `全选`, `撤销`, `重做`, using the exact selectors and shortcuts. All targets are nil. `install(on:)` assigns `application.mainMenu`.

- [ ] **Step 3: Install after editors are created and document behavior**

In `applicationDidFinishLaunching`, call `EditMenuController.install(on: NSApp)` after `windowController.show()`. Do not install before the editor exists. README lists all six shortcuts and clarifies that copy/paste works through the active editor.

- [ ] **Step 4: Run focused and full tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter EditMenuControllerTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

Expected: new tests and all existing tests PASS. If real paste/undo behavior differs on this AppKit version, preserve evidence and adjust only the menu wiring or responder-chain setup, never the content model.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatingWorkspaceCore/EditMenuController.swift Sources/FloatingWorkspace/AppDelegate.swift Tests/FloatingWorkspaceCoreTests/EditMenuControllerTests.swift README.md
git commit -m "feat: add standard edit menu shortcuts" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

---

## Completion Gate

Completion requires the exact menu selectors/shortcuts, real responder-chain copy/paste/cut/undo/redo evidence, and all previous tests. GitHub publication is a separate later action.
