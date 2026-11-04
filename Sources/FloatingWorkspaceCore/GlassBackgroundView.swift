import AppKit

@MainActor
final class GlassBackgroundView: NSView {
    let effectView = NSVisualEffectView()
    let gradientView = GradientView()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true

        addSubview(effectView)
        addSubview(gradientView)
        pinToEdges(effectView)
        pinToEdges(gradientView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ palette: WorkspacePalette, blankColor: NSColor? = nil) {
        effectView.isHidden = !palette.usesTransparency
        gradientView.isHidden = !palette.usesTransparency || blankColor != nil
        gradientView.colors = palette.gradientColors

        let backgroundColor: NSColor
        if let blankColor {
            backgroundColor = blankColor
        } else if palette.usesTransparency {
            backgroundColor = .clear
        } else {
            backgroundColor = palette.solidBackgroundColor
        }
        layer?.backgroundColor = backgroundColor.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func pinToEdges(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@MainActor
final class GradientView: NSView {
    var colors: [NSColor] = [] {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let gradient = NSGradient(colors: colors) else { return }
        gradient.draw(in: bounds, angle: -45)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
