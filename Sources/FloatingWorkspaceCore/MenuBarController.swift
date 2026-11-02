import AppKit

@MainActor
public final class MenuBarController: NSObject {
    public let statusItem: NSStatusItem
    private let windowController: FloatingWindowController

    public init(windowController: FloatingWindowController) {
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "悬浮工作台"
        ) {
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

        let togglePin = NSMenuItem(
            title: "切换置顶",
            action: #selector(togglePinned),
            keyEquivalent: ""
        )
        togglePin.target = self
        menu.addItem(togglePin)

        let quit = NSMenuItem(
            title: "退出悬浮工作台",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApplication.shared
        menu.addItem(quit)
        statusItem.menu = menu
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
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
