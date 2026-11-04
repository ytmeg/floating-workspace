import AppKit

@MainActor
public final class ApplicationIconController: NSObject {
    private let application: NSApplication
    private let bundle: Bundle
    private var appearanceObservation: NSKeyValueObservation?

    public init(application: NSApplication, bundle: Bundle = .main) {
        self.application = application
        self.bundle = bundle
        super.init()
        update()
        appearanceObservation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
    }

    public func update() {
        let isDark = application.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resourceName = isDark ? "AppIcon-Dark" : "AppIcon-Light"
        guard let url = bundle.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        image.accessibilityDescription = isDark ? "悬浮工作台深色图标" : "悬浮工作台浅色图标"
        application.applicationIconImage = image
    }
}
