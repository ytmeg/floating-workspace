import AppKit

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public let statusItem: NSStatusItem
    private let windowController: FloatingWindowController
    private let togglePinItem: NSMenuItem

    public init(windowController: FloatingWindowController, bundle: Bundle = .main) {
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        togglePinItem = NSMenuItem(
            title: "切换置顶",
            action: #selector(togglePinned),
            keyEquivalent: ""
        )
        super.init()

        let image: NSImage?
        if bundle.bundleURL.pathExtension == "app" {
            image = bundle.image(forResource: "MenuBarTemplate")
            image?.isTemplate = true
            image?.accessibilityDescription = "悬浮工作台"
        } else {
            image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "悬浮工作台"
            )
        }
        if let image {
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "浮"
        }

        let menu = NSMenu()
        let showHide = NSMenuItem(
            title: "显示／隐藏浮窗",
            action: #selector(showHidePanel),
            keyEquivalent: ""
        )
        showHide.target = self
        menu.addItem(showHide)

        togglePinItem.target = self
        menu.addItem(togglePinItem)

        let quit = NSMenuItem(
            title: "退出悬浮工作台",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApplication.shared
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        togglePinItem.state = windowController.isPinned ? .on : .off
    }

    @objc private func showHidePanel() {
        if windowController.panel.isVisible {
            windowController.hide()
        } else {
            windowController.show()
        }
    }

    @objc private func togglePinned() {
        windowController.togglePinned()
    }
}
