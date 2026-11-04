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
        XCTAssertFalse(controller.panel.isOpaque)
        XCTAssertEqual(controller.panel.backgroundColor, .clear)
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

    func testFirstLaunchWithoutSavedFrameCentersPanelOnVisibleScreen() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        let visible = try XCTUnwrap((controller.panel.screen ?? NSScreen.main)?.visibleFrame)
        XCTAssertEqual(controller.panel.frame.midX, visible.midX, accuracy: 1)
        XCTAssertTrue(visible.contains(controller.panel.frame))
        XCTAssertTrue(hasUsableTitlebar(controller.panel))
    }

    func testSavedFrameWithTinyScreenOverlapFallsBackToUsableTitlebar() throws {
        let rightmost = try XCTUnwrap(NSScreen.screens.max { $0.frame.maxX < $1.frame.maxX })
        let visible = rightmost.visibleFrame
        let savedFrame = NSRect(x: visible.maxX - 1, y: visible.maxY - 700, width: 640, height: 700)
        UserDefaults.standard.set(
            "\(Int(savedFrame.minX)) \(Int(savedFrame.minY)) 640 700 0 0 1512 949 ",
            forKey: "NSWindow Frame FloatingWorkspaceFrame"
        )

        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)

        XCTAssertNotEqual(controller.panel.frame, savedFrame)
        XCTAssertTrue(hasUsableTitlebar(controller.panel))
    }

    func testOversizedBlankResizeKeepsTitlebarOnVisibleScreen() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)
        let visible = try XCTUnwrap((controller.panel.screen ?? NSScreen.main)?.visibleFrame)

        controller.setBlankSize(width: 500, height: visible.height + 2000)

        XCTAssertTrue(visible.contains(controller.panel.frame))
        XCTAssertTrue(hasUsableTitlebar(controller.panel))
        XCTAssertEqual(controller.panel.frame.width, 500)
    }

    func testTitlebarPinButtonShowsStateAndTogglesSharedPin() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)
        let accessory = try XCTUnwrap(controller.panel.titlebarAccessoryViewControllers.first)
        let button = controller.pinButton

        XCTAssertTrue(button.isDescendant(of: accessory.view))
        XCTAssertEqual(button.accessibilityIdentifier(), "title-pin")
        XCTAssertEqual(button.state, .on)
        XCTAssertEqual(button.title, "已置顶")

        button.performClick(nil)
        XCTAssertFalse(doubles.store.content.isPinned)
        XCTAssertEqual(controller.panel.level, .normal)
        XCTAssertEqual(button.state, .off)
        XCTAssertEqual(button.title, "未置顶")

        controller.togglePinned()
        XCTAssertTrue(controller.isPinned)
        XCTAssertEqual(button.state, .on)
        XCTAssertEqual(button.title, "已置顶")

        button.performClick(nil)
        XCTAssertFalse(controller.isPinned)
        button.performClick(nil)
        XCTAssertTrue(controller.isPinned)
        XCTAssertEqual(controller.panel.level, .floating)
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
        XCTAssertEqual(controller.panel.backgroundColor, NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))

        doubles.store.update { $0.blankTitle = "" }
        XCTAssertEqual(controller.panel.title, "悬浮工作台")

        doubles.store.update { $0.selectedMode = .note }
        XCTAssertEqual(controller.panel.backgroundColor, .clear)
    }

    func testSetBlankSizeClampsEachDimensionToMinimum() throws {
        let doubles = try ContentStoreTestDoubles()
        let controller = FloatingWindowController(store: doubles.store)
        let visibleHeight = try XCTUnwrap((controller.panel.screen ?? NSScreen.main)?.visibleFrame.height)
        let requestedHeight = min(900, visibleHeight)

        controller.setBlankSize(width: 100, height: requestedHeight)
        XCTAssertEqual(controller.panel.frame.size, NSSize(width: 360, height: requestedHeight))

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

    private func hasUsableTitlebar(_ panel: NSPanel) -> Bool {
        let frame = panel.frame
        let titlebarHeight = frame.height - panel.contentRect(forFrameRect: frame).height
        let titlebar = NSRect(
            x: frame.minX,
            y: frame.maxY - titlebarHeight,
            width: frame.width,
            height: titlebarHeight
        )
        return NSScreen.screens.contains {
            let overlap = $0.visibleFrame.intersection(titlebar)
            return overlap.width >= 40 && overlap.height >= 20
        }
    }
}
