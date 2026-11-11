import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class EditMenuControllerTests: XCTestCase {
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
        XCTAssertEqual(menu.items.last?.keyEquivalentModifierMask, .shift)
    }

    func testRealTextViewCopyPasteCutAndUndoRedo() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: window.contentView!.bounds)
        text.allowsUndo = true
        window.contentView!.addSubview(text)
        let previousNextResponder = NSApp.nextResponder
        defer {
            NSApp.nextResponder = previousNextResponder
        }
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertTrue(window.firstResponder === text)
        NSApp.nextResponder = text
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
        let undoRedoResponder = UndoRedoResponder(undoManager: undoManager)
        let originalTextNextResponder = text.nextResponder
        text.nextResponder = undoRedoResponder
        undoRedoResponder.nextResponder = originalTextNextResponder
        defer { text.nextResponder = originalTextNextResponder }
        let undoAction = NSSelectorFromString("undo:")
        XCTAssertTrue(NSApp.sendAction(undoAction, to: nil, from: nil))
        XCTAssertEqual(text.string, "hello")
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil))
        XCTAssertEqual(text.string, "")
    }

    private func closeUndoGroup(using manager: UndoManager) {
        guard manager.groupingLevel > 0 else { return }
        let closed = expectation(forNotification: .NSUndoManagerDidCloseUndoGroup, object: manager)
        wait(for: [closed], timeout: 1)
    }
}

@MainActor
private final class UndoRedoResponder: NSResponder {
    private let manager: UndoManager

    init(undoManager: UndoManager) {
        manager = undoManager
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc func undo(_ sender: Any?) {
        manager.undo()
    }

    @objc func redo(_ sender: Any?) {
        manager.redo()
    }
}
