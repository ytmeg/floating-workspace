import AppKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class MenuBarControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSWindow.removeFrame(usingName: "FloatingWorkspaceFrame")
    }

    func testShowHideMenuActionUsesCurrentPanelVisibility() throws {
        let fixture = try makeFixture()
        let menu = try XCTUnwrap(fixture.menu.statusItem.menu)
        XCTAssertEqual(menu.items.map(\.title), ["显示／隐藏浮窗", "切换置顶", "退出悬浮工作台"])
        fixture.window.hide()

        try perform(menu.items[0])
        XCTAssertTrue(fixture.window.panel.isVisible)
        try perform(menu.items[0])
        XCTAssertFalse(fixture.window.panel.isVisible)
    }

    func testPinMenuActionTogglesSharedStoreAndPanel() throws {
        let fixture = try makeFixture()
        let menu = try XCTUnwrap(fixture.menu.statusItem.menu)

        try perform(menu.items[1])
        XCTAssertFalse(fixture.doubles.store.content.isPinned)
        XCTAssertEqual(fixture.window.panel.level, .normal)
        try perform(menu.items[1])
        XCTAssertTrue(fixture.doubles.store.content.isPinned)
        XCTAssertEqual(fixture.window.panel.level, .floating)
    }

    func testPinMenuItemStateRefreshesFromPinnedStateOnMenuUpdate() throws {
        let fixture = try makeFixture()
        let menu = try XCTUnwrap(fixture.menu.statusItem.menu)
        let delegate = try XCTUnwrap(menu.delegate)

        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items[1].state, .on)

        fixture.window.setPinned(false)
        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items[1].state, .off)

        fixture.window.togglePinned()
        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items[1].state, .on)
    }

    func testQuitMenuActionRoutesThroughApplicationTermination() throws {
        let fixture = try makeFixture()
        let menu = try XCTUnwrap(fixture.menu.statusItem.menu)
        let quit = menu.items[2]

        XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(quit.target === NSApp)
    }

    private func makeFixture() throws -> (
        doubles: ContentStoreTestDoubles,
        window: FloatingWindowController,
        menu: MenuBarController
    ) {
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let menu = MenuBarController(windowController: window)
        return (doubles, window, menu)
    }

    private func perform(_ item: NSMenuItem) throws {
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }
}
