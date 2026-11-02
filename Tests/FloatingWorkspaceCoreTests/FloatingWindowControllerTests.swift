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
