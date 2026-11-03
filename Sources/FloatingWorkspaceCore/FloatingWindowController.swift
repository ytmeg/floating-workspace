import AppKit
import Combine
import Foundation

@MainActor
public final class FloatingWindowController: NSObject {
    public let panel: NSPanel

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
        panel.minSize = NSSize(width: 360, height: 320)

        let workspace = WorkspaceViewController(store: store, windowController: self)
        workspaceViewController = workspace
        panel.contentViewController = workspace
        let frameAutosaveName: NSWindow.FrameAutosaveName = "FloatingWorkspaceFrame"
        panel.setFrameAutosaveName(frameAutosaveName)
        // AppKit's autosave key and string format are undocumented.
        // setFrame(from:) cascades the saved origin on this macOS, so restore it explicitly.
        if let savedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(frameAutosaveName)") {
            let restoredFrame = NSRectFromString(savedFrame)
            if restoredFrame.width >= panel.minSize.width,
               restoredFrame.height >= panel.minSize.height,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restoredFrame) }) {
                panel.setFrame(restoredFrame, display: false)
            }
        }
        workspace.updateBlankSizeFields()

        contentSubscription = store.$content.sink { [weak self] content in
            self?.apply(content)
        }
    }

    public func setPinned(_ pinned: Bool) {
        store.update { $0.isPinned = pinned }
    }

    public func togglePinned() {
        setPinned(!store.content.isPinned)
    }

    public func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func setBlankSize(width: Double, height: Double) {
        let size = NSSize(width: max(360, width), height: max(320, height))
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
    }

    private func apply(_ content: WorkspaceContent) {
        panel.level = content.isPinned ? .floating : .normal

        switch content.selectedMode {
        case .note:
            panel.title = "悬浮工作台"
            panel.backgroundColor = .windowBackgroundColor
        case .blank:
            panel.title = content.blankTitle.isEmpty ? "悬浮工作台" : content.blankTitle
            let color = content.blankBackground
            panel.backgroundColor = NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        case .image, .web:
            break
        }
    }
}
