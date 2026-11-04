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

    func testPackagedMenuTemplateIsAccessible() throws {
        let bundle = try makePackagedMenuBundle()
        let doubles = try ContentStoreTestDoubles()
        let window = FloatingWindowController(store: doubles.store)
        let menu = MenuBarController(windowController: window, bundle: bundle)
        let image = try XCTUnwrap(menu.statusItem.button?.image)

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.accessibilityDescription, "悬浮工作台")
        let expected = try XCTUnwrap(NSImage(
            contentsOf: repositoryURL().appendingPathComponent("Resources/Assets.xcassets/MenuBarTemplate.imageset/MenuBarTemplate-32.png")
        ))
        XCTAssertEqual(normalizedMenuPixels(image), normalizedMenuPixels(expected))
    }

    private func makePackagedMenuBundle() throws -> Bundle {
        if let packagedPath = ProcessInfo.processInfo.environment["FLOATING_WORKSPACE_MENU_TEST_BUNDLE"] {
            return try XCTUnwrap(Bundle(url: URL(fileURLWithPath: packagedPath)))
        }
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarControllerTests-\(UUID().uuidString).app")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        let info: NSDictionary = [
            "CFBundleIdentifier": "local.floatingworkspace.menu-tests.\(UUID().uuidString)",
            "CFBundlePackageType": "APPL",
        ]
        XCTAssertTrue(info.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"), atomically: true))
        try FileManager.default.copyItem(
            at: repositoryURL().appendingPathComponent("Resources/Assets.xcassets/MenuBarTemplate.imageset/MenuBarTemplate-32.png"),
            to: resourcesURL.appendingPathComponent("MenuBarTemplate.png")
        )
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func normalizedMenuPixels(_ image: NSImage) -> [UInt8]? {
        let width = 32
        let height = 32
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> [UInt8]? in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            image.draw(
                in: CGRect(x: 0, y: 0, width: width, height: height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            NSGraphicsContext.restoreGraphicsState()
            return Array(buffer)
        }
    }

    private func repositoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
