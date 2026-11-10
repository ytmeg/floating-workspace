import CoreGraphics
import Foundation

/// Shared geometry for image preview and, later, pixel export.
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
                  Self.isValid(crop: crop) else { return nil }

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

        public func displayPoint(forNormalized point: ImagePoint) -> CGPoint {
            CGPoint(
                x: imageRect.minX + CGFloat(point.x) * imageRect.width,
                y: imageRect.minY + CGFloat(point.y) * imageRect.height
            )
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
            guard Self.isValid(crop: crop) else { return nil }
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
            return Self.isValid(crop: crop) ? crop : nil
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

        private static func isValid(crop: ImageRect) -> Bool {
            crop.x.isFinite && crop.y.isFinite && crop.width.isFinite && crop.height.isFinite &&
            crop.x >= 0 && crop.y >= 0 && crop.width > 0 && crop.height > 0 &&
            crop.x + crop.width <= 1 && crop.y + crop.height <= 1
        }

        private static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
            CGPoint(
                x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY)
            )
        }
    }
}
