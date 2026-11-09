import AppKit
import Combine
import Foundation

@MainActor
public final class FloatingWindowController: NSObject {
    public let panel: NSPanel
    let pinButton = NSButton()

    public var isPinned: Bool { store.content.isPinned }

    private let store: ContentStore
    private var workspaceViewController: WorkspaceViewController?
    private var contentSubscription: AnyCancellable?

    public init(store: ContentStore) {
        self.store = store
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 360, height: 320)

        let workspace = WorkspaceViewController(store: store, windowController: self)
        workspaceViewController = workspace
        panel.contentViewController = workspace
        installPinAccessory()
        panel.center()
        let defaultFrame = panel.frame
        let frameAutosaveName: NSWindow.FrameAutosaveName = "FloatingWorkspaceFrame"
        panel.setFrameAutosaveName(frameAutosaveName)
        // AppKit's autosave key and string format are undocumented.
        // setFrame(from:) cascades the saved origin on this macOS, so restore it explicitly.
        if let savedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(frameAutosaveName)"),
           case let restoredFrame = NSRectFromString(savedFrame),
           restoredFrame.width >= panel.minSize.width,
           restoredFrame.height >= panel.minSize.height,
           hasUsableTitlebar(restoredFrame) {
            panel.setFrame(restoredFrame, display: false)
        } else {
            panel.setFrame(defaultFrame, display: false)
        }
        workspace.updateBlankSizeFields()

        contentSubscription = store.$content.sink { [weak self] content in
            self?.apply(content)
        }
    }

    public func setPinned(_ pinned: Bool) {
        store.update { $0.isPinned = pinned }
    }

    @objc public func togglePinned() {
        setPinned(!store.content.isPinned)
    }

    public func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func setBlankSize(width: Double, height: Double) {
        var frame = NSRect(
            origin: panel.frame.origin,
            size: NSSize(width: max(panel.minSize.width, width), height: max(panel.minSize.height, height))
        )
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = max(panel.minSize.width, min(frame.width, visible.width))
            frame.size.height = max(panel.minSize.height, min(frame.height, visible.height))
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)
    }

    private func installPinAccessory() {
        pinButton.bezelStyle = .recessed
        pinButton.setButtonType(.pushOnPushOff)
        pinButton.imagePosition = .imageLeading
        pinButton.font = NSFont.systemFont(ofSize: 13)
        pinButton.title = "未置顶"
        pinButton.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil)
        pinButton.sizeToFit()
        pinButton.target = self
        pinButton.action = #selector(togglePinned)
        pinButton.setAccessibilityIdentifier("title-pin")
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: pinButton.frame.width + 12, height: 28))
        container.addSubview(pinButton)
        NSLayoutConstraint.activate([
            pinButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            pinButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = container
        panel.addTitlebarAccessoryViewController(accessory)
    }

    /// Requires at least 40 x 20 pt of the title bar inside some screen's visible frame.
    private func hasUsableTitlebar(_ frame: NSRect) -> Bool {
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

    private func apply(_ content: WorkspaceContent) {
        panel.level = content.isPinned ? .floating : .normal
        pinButton.state = content.isPinned ? .on : .off
        pinButton.title = content.isPinned ? "已置顶" : "未置顶"
        pinButton.image = NSImage(
            systemSymbolName: content.isPinned ? "pin.fill" : "pin.slash",
            accessibilityDescription: nil
        )
        pinButton.toolTip = content.isPinned ? "点击取消置顶（⌃⌥⌘P）" : "点击置顶（⌃⌥⌘P）"

        switch content.selectedMode {
        case .note, .web:
            panel.title = "悬浮工作台"
            panel.backgroundColor = .clear
        case .blank:
            panel.title = content.blankTitle.isEmpty ? "悬浮工作台" : content.blankTitle
            let color = content.blankBackground
            panel.backgroundColor = NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        case .image:
            break
        }
    }
}
