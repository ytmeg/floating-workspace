import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class WorkspaceViewControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSWindow.removeFrame(usingName: "FloatingWorkspaceFrame")
    }

    func testPhaseOneControlsUseApprovedSizingAndIdentifiers() throws {
        let fixture = try makeWorkspace()

        XCTAssertTrue(fixture.workspace.noteButton.isEnabled)
        XCTAssertTrue(fixture.workspace.blankButton.isEnabled)
        XCTAssertFalse(fixture.workspace.imageButton.isEnabled)
        XCTAssertFalse(fixture.workspace.webButton.isEnabled)
        XCTAssertTrue(fixture.workspace.noteButton.isBordered)
        XCTAssertTrue(fixture.workspace.imageButton.isBordered)
        XCTAssertTrue(fixture.workspace.webButton.isBordered)
        XCTAssertTrue(fixture.workspace.blankButton.isBordered)
        XCTAssertEqual(fixture.workspace.noteTextView.font?.pointSize, 16)

        fixture.workspace.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(fixture.workspace.leftRail.frame.width, 76, accuracy: 0.001)

        XCTAssertEqual(fixture.workspace.noteButton.accessibilityIdentifier(), "mode-note")
        XCTAssertEqual(fixture.workspace.imageButton.accessibilityIdentifier(), "mode-image")
        XCTAssertEqual(fixture.workspace.webButton.accessibilityIdentifier(), "mode-web")
        XCTAssertEqual(fixture.workspace.blankButton.accessibilityIdentifier(), "mode-blank")
        XCTAssertEqual(fixture.workspace.noteTextView.accessibilityIdentifier(), "note-editor")
        XCTAssertEqual(fixture.workspace.blankTitleField.accessibilityIdentifier(), "blank-title")
        XCTAssertEqual(fixture.workspace.colorWell.accessibilityIdentifier(), "blank-color")
        XCTAssertEqual(fixture.workspace.widthField.accessibilityIdentifier(), "blank-width")
        XCTAssertEqual(fixture.workspace.heightField.accessibilityIdentifier(), "blank-height")
        XCTAssertEqual(fixture.workspace.saveStateLabel.accessibilityIdentifier(), "save-state")
    }

    func testDisabledModesLeaveSelectionUnchanged() throws {
        let fixture = try makeWorkspace()

        fixture.workspace.selectMode(.image)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .note)
        fixture.workspace.selectMode(.web)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .note)
    }

    func testSelectingBlankAndNoteModesUpdatesVisibleEditor() throws {
        let fixture = try makeWorkspace()

        fixture.workspace.selectMode(.blank)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .blank)
        XCTAssertFalse(fixture.workspace.blankContainer.isHidden)
        XCTAssertTrue(fixture.workspace.noteScrollView.isHidden)

        fixture.workspace.selectMode(.note)
        XCTAssertEqual(fixture.doubles.store.content.selectedMode, .note)
        XCTAssertFalse(fixture.workspace.noteScrollView.isHidden)
        XCTAssertTrue(fixture.workspace.blankContainer.isHidden)
    }

    func testNoteEditWritesPlainTextToStore() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.noteTextView.string = "编辑内容"

        fixture.workspace.textDidChange(Notification(
            name: NSText.didChangeNotification,
            object: fixture.workspace.noteTextView
        ))

        XCTAssertEqual(fixture.doubles.store.content.noteText, "编辑内容")
    }

    func testBlankTitleWritesStoreAndPanelTitle() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.selectMode(.blank)
        fixture.workspace.blankTitleField.stringValue = "项目空白"

        fixture.workspace.blankTitleChanged()

        XCTAssertEqual(fixture.doubles.store.content.blankTitle, "项目空白")
        XCTAssertEqual(fixture.window.panel.title, "项目空白")
    }

    func testBlankColorWritesSRGBChannelsToStore() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.colorWell.color = NSColor(
            srgbRed: 0.12,
            green: 0.34,
            blue: 0.56,
            alpha: 0.78
        )

        fixture.workspace.blankColorChanged()

        let color = fixture.doubles.store.content.blankBackground
        XCTAssertEqual(color.red, 0.12, accuracy: 0.001)
        XCTAssertEqual(color.green, 0.34, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.56, accuracy: 0.001)
        XCTAssertEqual(color.alpha, 0.78, accuracy: 0.001)
    }

    func testBlankSizeFieldsResizeRealPanel() throws {
        let fixture = try makeWorkspace()
        fixture.workspace.widthField.stringValue = "640"
        fixture.workspace.heightField.stringValue = "700"

        fixture.workspace.blankSizeChanged()

        XCTAssertEqual(fixture.window.panel.frame.size, NSSize(width: 640, height: 700))
    }

    func testSaveStateLabelMapsSavedSavingAndFailedStates() throws {
        let fixture = try makeWorkspace()
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "已保存")

        fixture.doubles.store.update { $0.noteText = "待保存" }
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "保存中")

        let failed = expectation(description: "save failed")
        fixture.doubles.store.flush { result in
            if case .failure = result { failed.fulfill() }
        }
        fixture.doubles.saver.completeFailure(at: 0)
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(fixture.workspace.saveStateLabel.stringValue, "保存失败")
    }

    func testFloatingWindowInstallsWorkspaceViewController() throws {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)

        XCTAssertTrue(window.panel.contentViewController is WorkspaceViewController)
    }

    private func makeWorkspace() throws -> (
        workspace: WorkspaceViewController,
        window: FloatingWindowController,
        doubles: ContentStoreTestDoubles
    ) {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let workspace = WorkspaceViewController(store: doubles.store, windowController: window)
        _ = workspace.view
        return (workspace, window, doubles)
    }
}
