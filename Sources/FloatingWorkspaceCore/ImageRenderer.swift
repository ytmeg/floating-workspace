import AppKit
import CoreGraphics
import Foundation

/// Shared geometry and drawing for image preview and pixel export.
/// Normalized coordinates use a bottom-left origin, matching CoreGraphics.
public enum ImageRenderer {
    public struct Layout: Equatable, Sendable {
        public let originalSize: CGSize
        public let viewSize: CGSize
        public let displayScale: Double
        public let normalizedCrop: ImageRect
        public let imageRect: CGRect
        public let cropRect: CGRect
        public let cropPixelRect: CGRect

        public init?(
            originalSize: CGSize,
            displayScale: Double,
            crop: ImageRect,
            viewSize: CGSize
        ) {
            guard originalSize.width.isFinite, originalSize.height.isFinite,
                  originalSize.width > 0, originalSize.height > 0,
                  viewSize.width.isFinite, viewSize.height.isFinite,
                  viewSize.width > 0, viewSize.height > 0,
                  displayScale.isFinite, (0.1...4).contains(displayScale),
                  let crop = Self.normalizedUnitCrop(crop) else { return nil }

            self.originalSize = originalSize
            self.viewSize = viewSize
            self.displayScale = displayScale
            normalizedCrop = crop

            let fitScale = min(
                viewSize.width / originalSize.width,
                viewSize.height / originalSize.height
            )
            let scale = fitScale * CGFloat(displayScale)
            let displaySize = CGSize(
                width: originalSize.width * scale,
                height: originalSize.height * scale
            )
            imageRect = CGRect(
                x: (viewSize.width - displaySize.width) / 2,
                y: (viewSize.height - displaySize.height) / 2,
                width: displaySize.width,
                height: displaySize.height
            )
            cropRect = CGRect(
                x: imageRect.minX + CGFloat(crop.x) * imageRect.width,
                y: imageRect.minY + CGFloat(crop.y) * imageRect.height,
                width: CGFloat(crop.width) * imageRect.width,
                height: CGFloat(crop.height) * imageRect.height
            )
            cropPixelRect = CGRect(
                x: CGFloat(crop.x) * originalSize.width,
                y: CGFloat(crop.y) * originalSize.height,
                width: CGFloat(crop.width) * originalSize.width,
                height: CGFloat(crop.height) * originalSize.height
            )
        }

        public var displayPointsPerOriginalPixel: CGFloat {
            imageRect.width / originalSize.width
        }

        func displayLineWidth(forOriginalWidth width: Double) -> CGFloat {
            max(1, CGFloat(width)) * displayPointsPerOriginalPixel
        }

        func displayArrowheadLength(forOriginalWidth width: Double) -> CGFloat {
            max(8, 3 * CGFloat(width)) * displayPointsPerOriginalPixel
        }

        func displayFontSize(forOriginalSize fontSize: Double) -> CGFloat {
            max(1, CGFloat(fontSize)) * displayPointsPerOriginalPixel
        }

        public func displayPoint(forNormalized point: ImagePoint) -> CGPoint {
            CGPoint(
                x: imageRect.minX + CGFloat(point.x) * imageRect.width,
                y: imageRect.minY + CGFloat(point.y) * imageRect.height
            )
        }

        /// Baseline-left text anchor shared by canvas preview and export rendering.
        public func textOrigin(forNormalized position: ImagePoint) -> CGPoint {
            displayPoint(forNormalized: position)
        }

        public func originalPoint(forNormalized point: ImagePoint) -> CGPoint {
            CGPoint(
                x: CGFloat(point.x) * originalSize.width,
                y: CGFloat(point.y) * originalSize.height
            )
        }

        public func normalizedPoint(forDisplay point: CGPoint) -> ImagePoint? {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= imageRect.minX, point.x <= imageRect.maxX,
                  point.y >= imageRect.minY, point.y <= imageRect.maxY else { return nil }
            return ImagePoint(
                x: Double((point.x - imageRect.minX) / imageRect.width),
                y: Double((point.y - imageRect.minY) / imageRect.height)
            )
        }

        public func normalizedPoint(forOriginal point: CGPoint) -> ImagePoint? {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= 0, point.y >= 0,
                  point.x <= originalSize.width, point.y <= originalSize.height else { return nil }
            return ImagePoint(
                x: Double(point.x / originalSize.width),
                y: Double(point.y / originalSize.height)
            )
        }

        public func originalPoint(forDisplay point: CGPoint) -> CGPoint? {
            normalizedPoint(forDisplay: point).map(originalPoint(forNormalized:))
        }

        public func displayRect(forNormalizedCrop crop: ImageRect) -> CGRect? {
            guard let crop = Self.normalizedUnitCrop(crop) else { return nil }
            return CGRect(
                x: imageRect.minX + CGFloat(crop.x) * imageRect.width,
                y: imageRect.minY + CGFloat(crop.y) * imageRect.height,
                width: CGFloat(crop.width) * imageRect.width,
                height: CGFloat(crop.height) * imageRect.height
            )
        }

        public func normalizedCrop(forDisplayRect rect: CGRect) -> ImageRect? {
            guard rect.origin.x.isFinite, rect.origin.y.isFinite,
                  rect.width.isFinite, rect.height.isFinite else { return nil }
            let visible = rect.standardized.intersection(imageRect)
            guard !visible.isNull, !visible.isEmpty else { return nil }
            let x = Double((visible.minX - imageRect.minX) / imageRect.width)
            let y = Double((visible.minY - imageRect.minY) / imageRect.height)
            let width = Double(visible.width / imageRect.width)
            let height = Double(visible.height / imageRect.height)
            let crop = ImageRect(x: x, y: y, width: width, height: height)
            return Self.normalizedUnitCrop(crop)
        }

        /// Converts a drag into an aspect-preserving crop, clipping both endpoints to the image.
        public func normalizedCrop(from start: CGPoint, to end: CGPoint) -> ImageRect? {
            let clippedStart = Self.clamp(start, to: imageRect)
            let clippedEnd = Self.clamp(end, to: imageRect)
            let deltaX = clippedEnd.x - clippedStart.x
            let deltaY = clippedEnd.y - clippedStart.y
            let aspect = originalSize.width / originalSize.height
            let desiredWidth = max(abs(deltaX), abs(deltaY) * aspect)
            let availableWidth = deltaX >= 0
                ? imageRect.maxX - clippedStart.x
                : clippedStart.x - imageRect.minX
            let availableHeight = deltaY >= 0
                ? imageRect.maxY - clippedStart.y
                : clippedStart.y - imageRect.minY
            let width = min(desiredWidth, min(availableWidth, availableHeight * aspect))
            let height = width / aspect
            guard width.isFinite, width > 0, height.isFinite, height > 0 else { return nil }
            let rect = CGRect(
                x: deltaX >= 0 ? clippedStart.x : clippedStart.x - width,
                y: deltaY >= 0 ? clippedStart.y : clippedStart.y - height,
                width: width,
                height: height
            )
            return normalizedCrop(forDisplayRect: rect)
        }

        static func normalizedUnitCrop(_ crop: ImageRect) -> ImageRect? {
            let tolerance = 0.000_000_001
            guard crop.x.isFinite, crop.y.isFinite, crop.width.isFinite, crop.height.isFinite,
                  crop.x >= -tolerance, crop.y >= -tolerance,
                  crop.width > 0, crop.height > 0,
                  crop.width <= 1 + tolerance, crop.height <= 1 + tolerance,
                  crop.x + crop.width <= 1 + tolerance,
                  crop.y + crop.height <= 1 + tolerance else { return nil }
            let width = min(crop.width, 1)
            let height = min(crop.height, 1)
            // Preserve dimensions (and therefore aspect) by moving only the origin back inside.
            let x = min(max(crop.x, 0), 1 - width)
            let y = min(max(crop.y, 0), 1 - height)
            return ImageRect(x: x, y: y, width: width, height: height)
        }

        private static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
            CGPoint(
                x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY)
            )
        }
    }

    typealias BitmapContextFactory = (Int, Int, CGColorSpace) -> CGContext?

    /// Renders in original-image pixel coordinates. The context translation defines the
    /// export mapping: exportPixel = originalPixel - cropRect.origin, with no resampling.
    @MainActor
    static func render(
        image: CGImage,
        annotations: [ImageAnnotation],
        cropRect: CGRect,
        contextFactory: BitmapContextFactory? = nil
    ) throws -> CGImage {
        guard cropRect.origin.x.isFinite, cropRect.origin.y.isFinite,
              cropRect.width.isFinite, cropRect.height.isFinite,
              cropRect.width >= 1, cropRect.height >= 1,
              cropRect.width <= CGFloat(Int.max), cropRect.height <= CGFloat(Int.max),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw error("无法创建图片渲染上下文", code: 1)
        }
        let originalSize = CGSize(width: image.width, height: image.height)
        guard let layout = Layout(
            originalSize: originalSize,
            displayScale: 1,
            crop: .full,
            viewSize: originalSize
        ) else {
            throw error("无法创建图片渲染上下文", code: 1)
        }
        let context: CGContext?
        if let contextFactory {
            context = contextFactory(
                Int(cropRect.width),
                Int(cropRect.height),
                colorSpace
            )
        } else {
            context = makeBitmapContext(
                width: Int(cropRect.width),
                height: Int(cropRect.height),
                colorSpace: colorSpace
            )
        }
        guard let context else {
            throw error("无法创建图片渲染上下文", code: 1)
        }

        context.interpolationQuality = .none
        context.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        context.draw(image, in: layout.imageRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for annotation in annotations {
            draw(annotation, in: context, layout: layout)
        }
        guard let rendered = context.makeImage() else {
            throw error("无法生成导出位图", code: 2)
        }
        return rendered
    }

    @MainActor
    static func draw(
        _ annotation: ImageAnnotation,
        in context: CGContext,
        layout: Layout
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        switch annotation {
        case let .pencil(points, color, width):
            guard let first = points.first else { return }
            let displayPoints = points.map(layout.displayPoint(forNormalized:))
            let displayWidth = layout.displayLineWidth(forOriginalWidth: width)
            context.setStrokeColor(cgColor(color))
            context.setFillColor(cgColor(color))
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
                .font: NSFont.systemFont(ofSize: layout.displayFontSize(forOriginalSize: fontSize)),
                .foregroundColor: nsColor(color)
            ]
            // Match the canvas exactly: this is the attributed text box's bottom-left,
            // not a font baseline. Do not replace with CTLineDraw or a flipped context.
            NSAttributedString(string: content, attributes: attributes)
                .draw(at: layout.textOrigin(forNormalized: position))
        case let .arrow(start, end, color, width):
            let displayStart = layout.displayPoint(forNormalized: start)
            let displayEnd = layout.displayPoint(forNormalized: end)
            let displayWidth = layout.displayLineWidth(forOriginalWidth: width)
            context.setStrokeColor(cgColor(color))
            context.setFillColor(cgColor(color))
            context.setLineWidth(displayWidth)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: displayStart)
            context.addLine(to: displayEnd)
            context.strokePath()

            let angle = atan2(displayEnd.y - displayStart.y, displayEnd.x - displayStart.x)
            let headLength = layout.displayArrowheadLength(forOriginalWidth: width)
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

    private static func makeBitmapContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(
            domain: "ImageRenderer",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
