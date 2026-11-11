import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class EditMenuControllerTests: XCTestCase {
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var testWindow: NSWindow?

    override func tearDown() {
        testWindow?.orderOut(nil)
        testWindow = nil
        if let previousActivationPolicy {
            _ = NSApp.setActivationPolicy(previousActivationPolicy)
        }
        previousActivationPolicy = nil
        super.tearDown()
    }

    func testMenuUsesStandardSelectorsAndShortcuts() {
        let menu = EditMenuController.makeMenu()
        let actions = menu.items.map(\.title)
        XCTAssertEqual(actions, ["复制", "粘贴", "剪切", "全选", "撤销", "重做"])
        let selectors = menu.items.map(\.action)
        XCTAssertEqual(selectors, [
            #selector(NSTextView.copy(_:)), #selector(NSTextView.paste(_:)), #selector(NSTextView.cut(_:)),
            #selector(NSTextView.selectAll(_:)), NSSelectorFromString("undo:"), NSSelectorFromString("redo:")
        ])
        for item in menu.items { XCTAssertNil(item.target) }
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["c", "v", "x", "a", "z", "Z"])
        XCTAssertEqual(menu.items.map(\.keyEquivalentModifierMask), [
            .command, .command, .command, .command, .command, [.command, .shift]
        ])
    }

    func testRealTextViewCopyPasteCutAndUndoRedo() throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        testWindow = window
        let text = NSTextView(frame: window.contentView!.bounds)
        text.allowsUndo = true
        window.contentView!.addSubview(text)
        previousActivationPolicy = NSApp.activationPolicy()
        XCTAssertTrue(NSApp.setActivationPolicy(.regular))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        waitForKeyWindow(window)
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertTrue(window.firstResponder === text)
        text.string = "hello"
        text.selectAll(nil)
        XCTAssertTrue(NSApp.sendAction(#selector(NSTextView.copy(_:)), to: nil, from: nil))
        text.string = ""
        XCTAssertTrue(NSApp.sendAction(#selector(NSTextView.paste(_:)), to: nil, from: nil))
        XCTAssertEqual(text.string, "hello")
        let undoManager = try XCTUnwrap(text.undoManager)
        closeUndoGroup(using: undoManager)
        XCTAssertTrue(NSApp.sendAction(#selector(NSTextView.selectAll(_:)), to: nil, from: nil))
        XCTAssertTrue(NSApp.sendAction(#selector(NSTextView.cut(_:)), to: nil, from: nil))
        XCTAssertEqual(text.string, "")
        closeUndoGroup(using: undoManager)
        let undoAction = NSSelectorFromString("undo:")
        XCTAssertTrue(NSApp.sendAction(undoAction, to: nil, from: nil))
        XCTAssertEqual(text.string, "hello")
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil))
        XCTAssertEqual(text.string, "")
    }

    private func waitForKeyWindow(_ window: NSWindow, timeout: TimeInterval = 2) {
        let becameKey = expectation(description: "Window became key")
        let timer = Timer(timeInterval: 0.01, repeats: true) { timer in
            guard window.isKeyWindow else { return }
            becameKey.fulfill()
            timer.invalidate()
        }
        RunLoop.current.add(timer, forMode: .common)
        wait(for: [becameKey], timeout: timeout)
        timer.invalidate()
        XCTAssertTrue(window.isKeyWindow)
    }

    private func closeUndoGroup(using manager: UndoManager) {
        guard manager.groupingLevel > 0 else { return }
        let closed = expectation(forNotification: .NSUndoManagerDidCloseUndoGroup, object: manager)
        wait(for: [closed], timeout: 1)
    }
}
