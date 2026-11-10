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
    public var onPencil: (([ImagePoint]) -> Void)?
    public var onText: ((String, ImagePoint) -> Void)?
    public var onArrow: ((ImagePoint, ImagePoint) -> Void)?

    private enum CropInteraction {
        case new
        case move(ImageRect)
        case resize(ImageRect)
    }

    private enum Interaction {
        case pencil([ImagePoint])
        case arrow(start: ImagePoint, current: CGPoint)
        case crop(kind: CropInteraction, start: CGPoint)
    }

    private var interaction: Interaction?
    private var editingCrop: ImageRect?

    var layout: ImageRenderer.Layout? {
        guard let image, let document else { return nil }
        return ImageRenderer.Layout(
            originalSize: CGSize(width: image.width, height: image.height),
            displayScale: document.displayScale,
            crop: document.cropRect,
            viewSize: bounds.size
        )
    }

    public override var acceptsFirstResponder: Bool { true }

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
            interaction = .pencil([normalized])
        case .text:
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            onText?(textContentProvider?() ?? textContent, normalized)
        case .arrow:
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            interaction = .arrow(start: normalized, current: point)
        }
    }

    func continueInteraction(at point: CGPoint) {
        guard let layout, let interaction else { return }
        switch interaction {
        case let .pencil(points):
            guard let normalized = layout.normalizedPoint(forDisplay: point) else { return }
            self.interaction = .pencil(points + [normalized])
        case let .arrow(start, _):
            self.interaction = .arrow(start: start, current: point)
        case let .crop(kind, start):
            editingCrop = crop(for: kind, start: start, current: point, layout: layout)
        }
        needsDisplay = true
    }

    func endInteraction(at point: CGPoint) {
        guard let layout, let interaction else { return }
        switch interaction {
        case let .pencil(points):
            let finalPoints: [ImagePoint]
            if let normalized = layout.normalizedPoint(forDisplay: point) {
                finalPoints = points + [normalized]
            } else {
                finalPoints = points
            }
            self.interaction = nil
            if !finalPoints.isEmpty {
                onPencil?(finalPoints)
            }
        case let .arrow(start, _):
            self.interaction = nil
            if let end = layout.normalizedPoint(forDisplay: point) {
                let displayStart = layout.displayPoint(forNormalized: start)
                let displayEnd = layout.displayPoint(forNormalized: end)
                let displayLength = hypot(displayEnd.x - displayStart.x, displayEnd.y - displayStart.y)
                if displayLength >= 1 {
                    onArrow?(start, end)
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

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard let context = NSGraphicsContext.current?.cgContext,
              let layout, let image, let document else { return }

        context.draw(image, in: layout.imageRect)
        for annotation in document.annotations {
            draw(annotation, in: context, layout: layout)
        }
        if case let .pencil(points) = interaction {
            draw(.pencil(points: points, color: annotationColor, width: 2), in: context, layout: layout)
        }
        if case let .arrow(start, current) = interaction,
           let end = layout.normalizedPoint(forDisplay: current) {
            draw(.arrow(start: start, end: end, color: annotationColor, width: 2), in: context, layout: layout)
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

    private func resizeHandle(for cropRect: CGRect) -> CGRect {
        CGRect(x: cropRect.maxX - 5, y: cropRect.minY - 5, width: 10, height: 10)
    }

    private func draw(
        _ annotation: ImageAnnotation,
        in context: CGContext,
        layout: ImageRenderer.Layout
    ) {
        switch annotation {
        case let .pencil(points, color, width):
            guard let first = points.first else { return }
            let displayPoints = points.map(layout.displayPoint(forNormalized:))
            let displayWidth = max(1, CGFloat(width) * layout.displayPointsPerOriginalPixel)
            context.setStrokeColor(Self.cgColor(color))
            context.setFillColor(Self.cgColor(color))
            context.setLineWidth(displayWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if displayPoints.count == 1, let point = displayPoints.first {
                context.fillEllipse(in: CGRect(
                    x: point.x - displayWidth / 2,
                    y: point.y - displayWidth / 2,
                    width: displayWidth,
                    height: displayWidth
                ))
                return
            }
            context.beginPath()
            context.move(to: layout.displayPoint(forNormalized: first))
            for point in displayPoints.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        case let .text(content, color, fontSize, position):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(1, CGFloat(fontSize) * layout.displayPointsPerOriginalPixel)),
                .foregroundColor: Self.nsColor(color)
            ]
            NSAttributedString(string: content, attributes: attributes)
                .draw(at: layout.textOrigin(forNormalized: position))
        case let .arrow(start, end, color, width):
            let displayStart = layout.displayPoint(forNormalized: start)
            let displayEnd = layout.displayPoint(forNormalized: end)
            let displayWidth = max(1, CGFloat(width) * layout.displayPointsPerOriginalPixel)
            context.setStrokeColor(Self.cgColor(color))
            context.setFillColor(Self.cgColor(color))
            context.setLineWidth(displayWidth)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: displayStart)
            context.addLine(to: displayEnd)
            context.strokePath()

            let angle = atan2(displayEnd.y - displayStart.y, displayEnd.x - displayStart.x)
            let headLength = max(8, displayWidth * 3)
            let headAngle = CGFloat.pi / 6
            let first = CGPoint(
                x: displayEnd.x - headLength * cos(angle - headAngle),
                y: displayEnd.y - headLength * sin(angle - headAngle)
            )
            let second = CGPoint(
                x: displayEnd.x - headLength * cos(angle + headAngle),
                y: displayEnd.y - headLength * sin(angle + headAngle)
            )
            context.beginPath()
            context.move(to: displayEnd)
            context.addLine(to: first)
            context.addLine(to: second)
            context.closePath()
            context.fillPath()
        }
    }

    private static func nsColor(_ color: RGBAColor) -> NSColor {
        NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        nsColor(color).cgColor
    }
}
