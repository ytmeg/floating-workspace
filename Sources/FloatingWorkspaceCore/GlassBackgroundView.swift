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

    /// `blankColor` is painted by the panel itself; repainting it here would composite translucent colors twice.
    func apply(_ palette: WorkspacePalette, blankColor: NSColor? = nil) {
        effectView.isHidden = !palette.usesTransparency || blankColor != nil
        gradientView.isHidden = !palette.usesTransparency || blankColor != nil
        gradientView.colors = palette.gradientColors

        let backgroundColor: NSColor
        if blankColor != nil || palette.usesTransparency {
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
    private(set) var invalidationCount = 0

    var colors: [NSColor] = [] {
        didSet {
            guard colors != oldValue else { return }
            invalidationCount += 1
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let gradient = NSGradient(colors: colors) else { return }
        gradient.draw(in: bounds, angle: -45)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


/// Draws the 1 pt edge above the content. The top edge is left to the titlebar separator, and the bottom corners
/// follow the titled panel's rounded mask instead of being clipped off by it.
@MainActor
final class GlassBorderView: NSView {
    /// Measured from the titled `NSPanel` mask on macOS 26; AppKit does not publish this radius.
    static let bottomCornerRadius: CGFloat = 12

    private(set) var strokeLayer: CAShapeLayer?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let stroke = CAShapeLayer()
        stroke.fillColor = nil
        stroke.lineWidth = 1
        layer?.addSublayer(stroke)
        strokeLayer = stroke
        updatePath()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ palette: WorkspacePalette) {
        strokeLayer?.strokeColor = palette.borderColor.cgColor
    }

    override func layout() {
        super.layout()
        updatePath()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePath()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        strokeLayer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updatePath() {
        guard let strokeLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayer.frame = bounds
        // The layer is unflipped: y = 0 is the bottom edge and y = maxY meets the titlebar.
        let inset: CGFloat = 0.5
        let radius = min(Self.bottomCornerRadius, bounds.width / 2, bounds.height)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: inset, y: bounds.maxY))
        path.addLine(to: CGPoint(x: inset, y: radius))
        path.addArc(
            center: CGPoint(x: radius, y: radius),
            radius: radius - inset,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: inset))
        path.addArc(
            center: CGPoint(x: bounds.maxX - radius, y: radius),
            radius: radius - inset,
            startAngle: .pi * 1.5,
            endAngle: 0,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bounds.maxX - inset, y: bounds.maxY))
        strokeLayer.path = path
        CATransaction.commit()
    }
}
