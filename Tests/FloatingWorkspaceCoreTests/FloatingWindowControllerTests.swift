import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class FloatingWindowControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSWindow.removeFrame(usingName: "FloatingWorkspaceFrame")
    }

    func testPanelUsesFloatingWorkspaceDefaults() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        XCTAssertTrue(controller.panel.isFloatingPanel)
        XCTAssertFalse(controller.panel.hidesOnDeactivate)
        XCTAssertEqual(controller.panel.frameAutosaveName, "FloatingWorkspaceFrame")
        XCTAssertEqual(controller.panel.minSize, NSSize(width: 360, height: 320))
        XCTAssertEqual(controller.panel.level, .floating)
        XCTAssertTrue(controller.panel.styleMask.contains(.titled))
        XCTAssertTrue(controller.panel.styleMask.contains(.closable))
        XCTAssertTrue(controller.panel.styleMask.contains(.miniaturizable))
        XCTAssertTrue(controller.panel.styleMask.contains(.resizable))
        XCTAssertEqual(
            controller.panel.contentRect(forFrameRect: controller.panel.frame).size,
            NSSize(width: 520, height: 540)
        )
        XCTAssertEqual(controller.panel.title, "悬浮工作台")
        XCTAssertEqual(controller.panel.backgroundColor, .windowBackgroundColor)
    }

    func testSavedFrameIsRestoredAfterWorkspaceContentInstallation() throws {
        let savedFrame = NSRect(x: 100, y: 160, width: 640, height: 700)
        let saver = NSWindow(
            contentRect: savedFrame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        saver.setFrame(savedFrame, display: false)
        saver.saveFrame(usingName: "FloatingWorkspaceFrame")

        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        XCTAssertEqual(controller.panel.frame, savedFrame)
    }

    func testSavedBlankFrameUpdatesSizeFieldsAfterRestore() throws {
        let savedFrame = NSRect(x: 100, y: 160, width: 640, height: 700)
        let saver = NSWindow(
            contentRect: savedFrame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        saver.setFrame(savedFrame, display: false)
        saver.saveFrame(usingName: "FloatingWorkspaceFrame")

        let doubles = try ContentStoreTestDoubles()
        doubles.store.update { $0.selectedMode = .blank }
        let controller = FloatingWindowController(store: doubles.store)
        let workspace = try XCTUnwrap(controller.panel.contentViewController as? WorkspaceViewController)

        XCTAssertEqual(workspace.widthField.stringValue, "640")
        XCTAssertEqual(workspace.heightField.stringValue, "700")
    }

    func testOffScreenSavedFrameEndsOnVisibleScreen() throws {
        UserDefaults.standard.set(
            "-50000 160 640 700 0 0 1512 949 ",
            forKey: "NSWindow Frame FloatingWorkspaceFrame"
        )

        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(controller.panel.frame) })
    }

    func testGarbageSavedFrameDoesNotProduceZeroOrBelowMinimumFrame() throws {
        UserDefaults.standard.set("not-a-frame", forKey: "NSWindow Frame FloatingWorkspaceFrame")

        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        XCTAssertNotEqual(controller.panel.frame, .zero)
        XCTAssertGreaterThanOrEqual(controller.panel.frame.width, controller.panel.minSize.width)
        XCTAssertGreaterThanOrEqual(controller.panel.frame.height, controller.panel.minSize.height)
    }

    func testPinningUpdatesStoreAndPanelLevel() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        controller.setPinned(false)
        XCTAssertEqual(controller.panel.level, .normal)
        XCTAssertFalse(doubles.store.content.isPinned)
        controller.togglePinned()
        XCTAssertEqual(controller.panel.level, .floating)
        XCTAssertTrue(doubles.store.content.isPinned)
    }

    func testBlankContentUpdatesTitleAndSRGBBackground() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        doubles.store.update {
            $0.selectedMode = .blank
            $0.blankTitle = "自定义标题"
            $0.blankBackground = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        }
        XCTAssertEqual(controller.panel.title, "自定义标题")
        XCTAssertEqual(controller.panel.backgroundColor, NSColor(red: 1, green: 0, blue: 0, alpha: 1))

        doubles.store.update { $0.blankTitle = "" }
        XCTAssertEqual(controller.panel.title, "悬浮工作台")
    }

    func testSetBlankSizeClampsEachDimensionToMinimum() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        controller.setBlankSize(width: 100, height: 900)
        XCTAssertEqual(controller.panel.frame.size, NSSize(width: 360, height: 900))

        controller.setBlankSize(width: 500, height: 100)
        XCTAssertEqual(controller.panel.frame.size, NSSize(width: 500, height: 320))
    }

    func testShowAndHideControlPanelVisibility() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        controller.show()
        XCTAssertTrue(controller.panel.isVisible)
        controller.hide()
        XCTAssertFalse(controller.panel.isVisible)
    }
}
