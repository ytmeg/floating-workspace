import AppKit
import CoreGraphics
import Foundation

public enum ImageEditTool: String, Sendable {
    case pencil
    case text
    case arrow
}

@MainActor
public final class ImageCanvasView: NSView {
    public var image: CGImage? {
        didSet { needsDisplay = true }
    }
    public var document: ImageDocument? {
        didSet { needsDisplay = true }
    }
    public var tool: ImageEditTool = .pencil
    public var isCropEditingEnabled = false
    public var textContent = ""
    public var textContentProvider: (() -> String)?
    public var annotationColor = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

    public var onCrop: ((ImageRect) -> Void)?
    /// Sizes are in original pixels, converted from fixed screen sizes at creation time.
    public var onPencil: (([ImagePoint], Double) -> Void)?
    public var onText: ((String, ImagePoint, Double) -> Void)?
    public var onArrow: ((ImagePoint, ImagePoint, Double) -> Void)?

    static let screenStrokeWidth: CGFloat = 2
    static let screenFontSize: CGFloat = 16

    private enum CropInteraction {
        case new
        case move(ImageRect)
        case resize(ImageRect)
    }

    private enum Interaction {
        case pencil([ImagePoint], width: Double)
        case arrow(start: ImagePoint, current: CGPoint, width: Double)
        case crop(kind: CropInteraction, start: CGPoint)
    }

    private var interaction: Interaction?
    private var editingCrop: ImageRect?
    private var viewportSize: CGSize?
    private(set) var contentLayoutOffset: CGPoint = .zero

    var layout: ImageRenderer.Layout? {
        guard let image, let document else { return nil }
        return ImageRenderer.Layout(
            originalSize: CGSize(width: image.width, height: image.height),
            displayScale: document.displayScale,
            crop: document.cropRect,
            viewSize: viewportSize ?? bounds.size
        )
    }

    public override var acceptsFirstResponder: Bool { true }

    func updateViewportSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        viewportSize = size
        updateContentLayout()
    }

    func updateContentLayout() {
        guard let viewportSize else { return }
        let viewport = CGRect(origin: .zero, size: viewportSize)
        let content = layout?.imageRect.union(viewport) ?? viewport
        contentLayoutOffset = CGPoint(x: -content.minX, y: -content.minY)
        frame.size = content.size
        needsDisplay = true
    }

    private func layoutPoint(forCanvasPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - contentLayoutOffset.x, y: point.y - contentLayoutOffset.y)
    }

    public override func mouseDown(with event: NSEvent) {
        beginInteraction(at: convert(event.locationInWindow, from: nil))
    }

    public override func mouseDragged(with event: NSEvent) {
        continueInteraction(at: convert(event.locationInWindow, from: nil))
    }

    public override func mouseUp(with event: NSEvent) {
        endInteraction(at: convert(event.locationInWindow, from: nil))
    }

    func beginInteraction(at point: CGPoint) {
        let point = layoutPoint(forCanvasPoint: point)
        guard let layout else { return }
        interaction = nil
        editingCrop = nil

        if isCropEditingEnabled {
            let initial = layout.normalizedCrop
            let handle = resizeHandle(for: layout.cropRect)
            let kind: CropInteraction
            if handle.contains(point) {
                kind = .resize(initial)
            } else {
                guard layout.normalizedPoint(forDisplay: point) != nil else { return }
                if initial != .full, layout.cropRect.contains(point) {
                    kind = .move(initial)
                } else {
                    kind = .new
                }
            }
            interaction = .crop(kind: kind, start: point)
            editingCrop = initial
            return
        }

        switch tool {
        case .pencil:
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            interaction = .pencil([normalized], width: Self.originalSize(Self.screenStrokeWidth, layout: layout))
        case .text:
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            onText?(
                textContentProvider?() ?? textContent,
                normalized,
                Self.originalSize(Self.screenFontSize, layout: layout)
            )
        case .arrow:
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            interaction = .arrow(
                start: normalized,
                current: point,
                width: Self.originalSize(Self.screenStrokeWidth, layout: layout)
            )
        }
    }

    func continueInteraction(at point: CGPoint) {
        let point = layoutPoint(forCanvasPoint: point)
        guard let layout, let interaction else { return }
        switch interaction {
        case let .pencil(points, width):
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            self.interaction = .pencil(points + [normalized], width: width)
        case let .arrow(start, _, width):
            self.interaction = .arrow(start: start, current: point, width: width)
        case let .crop(kind, start):
            editingCrop = crop(for: kind, start: start, current: point, layout: layout)
        }
        needsDisplay = true
    }

    func endInteraction(at point: CGPoint) {
        let point = layoutPoint(forCanvasPoint: point)
        guard let layout, let interaction else { return }
        switch interaction {
        case let .pencil(points, width):
            let finalPoints: [ImagePoint]
            if let normalized = layout.normalizedPoint(forDisplay: point) {
                finalPoints = points + [normalized]
            } else {
                finalPoints = points
            }
            self.interaction = nil
            if !finalPoints.isEmpty {
                onPencil?(finalPoints, width)
            }
        case let .arrow(start, _, width):
            self.interaction = nil
            if let end = layout.normalizedPoint(forDisplay: point) {
                let displayStart = layout.displayPoint(forNormalized: start)
                let displayEnd = layout.displayPoint(forNormalized: end)
                let displayLength = hypot(displayEnd.x - displayStart.x, displayEnd.y - displayStart.y)
                if displayLength >= 1 {
                    onArrow?(start, end, width)
                }
            }
        case let .crop(kind, start):
            let crop = crop(for: kind, start: start, current: point, layout: layout)
            self.interaction = nil
            editingCrop = nil
            if let crop {
                onCrop?(crop)
            }
        }
        needsDisplay = true
    }

    /// The annotation being dragged, drawn with the same model value that will be persisted.
    var inProgressAnnotation: ImageAnnotation? {
        guard let layout else { return nil }
        switch interaction {
        case let .pencil(points, width):
            return .pencil(points: points, color: annotationColor, width: width)
        case let .arrow(start, current, width):
            guard let end = layout.normalizedPoint(forDisplay: current) else { return nil }
            return .arrow(start: start, end: end, color: annotationColor, width: width)
        case .crop, nil:
            return nil
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard let context = NSGraphicsContext.current?.cgContext,
              let layout, let image, let document else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: contentLayoutOffset.x, y: contentLayoutOffset.y)
        context.draw(image, in: layout.imageRect)
        for annotation in document.annotations {
            ImageRenderer.draw(annotation, in: context, layout: layout)
        }
        if let inProgressAnnotation {
            ImageRenderer.draw(inProgressAnnotation, in: context, layout: layout)
        }

        let crop = editingCrop ?? document.cropRect
        if let cropRect = layout.displayRect(forNormalizedCrop: crop) {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(cropRect)
            context.restoreGState()
            if isCropEditingEnabled {
                context.setFillColor(NSColor.systemBlue.cgColor)
                context.fill(resizeHandle(for: cropRect))
            }
        }
    }

    private func crop(
        for kind: CropInteraction,
        start: CGPoint,
        current: CGPoint,
        layout: ImageRenderer.Layout
    ) -> ImageRect? {
        switch kind {
        case .new:
            return layout.normalizedCrop(from: start, to: current)
        case let .resize(initial):
            guard let initialRect = layout.displayRect(forNormalizedCrop: initial) else { return nil }
            let anchor = CGPoint(x: initialRect.minX, y: initialRect.maxY)
            return layout.normalizedCrop(from: anchor, to: current)
        case let .move(initial):
            guard let initialRect = layout.displayRect(forNormalizedCrop: initial) else { return nil }
            let deltaX = current.x - start.x
            let deltaY = current.y - start.y
            let x = min(
                max(initialRect.minX + deltaX, layout.imageRect.minX),
                layout.imageRect.maxX - initialRect.width
            )
            let y = min(
                max(initialRect.minY + deltaY, layout.imageRect.minY),
                layout.imageRect.maxY - initialRect.height
            )
            return layout.normalizedCrop(forDisplayRect: CGRect(
                x: x,
                y: y,
                width: initialRect.width,
                height: initialRect.height
            ))
        }
    }

    /// Converts a fixed on-screen size to original pixels for the current fit and zoom.
    private static func originalSize(_ screenSize: CGFloat, layout: ImageRenderer.Layout) -> Double {
        Double(screenSize / layout.displayPointsPerOriginalPixel)
    }

    private func resizeHandle(for cropRect: CGRect) -> CGRect {
        CGRect(x: cropRect.maxX - 5, y: cropRect.minY - 5, width: 10, height: 10)
    }

}
