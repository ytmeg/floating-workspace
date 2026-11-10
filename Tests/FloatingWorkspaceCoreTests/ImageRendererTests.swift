import AppKit
import CoreGraphics
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ImageRendererTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }
    private func makeLayout(
        originalSize: CGSize = CGSize(width: 200, height: 100),
        scale: Double = 1,
        crop: ImageRect = .full,
        viewSize: CGSize = CGSize(width: 400, height: 400),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ImageRenderer.Layout {
        try XCTUnwrap(ImageRenderer.Layout(
            originalSize: originalSize,
            displayScale: scale,
            crop: crop,
            viewSize: viewSize
        ), file: file, line: line)
    }

    private func assertPoint(
        _ actual: CGPoint,
        x: CGFloat,
        y: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, x, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.y, y, accuracy: 0.000_000_001, file: file, line: line)
    }

    private func assertRect(
        _ actual: CGRect,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, x, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, y, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.size.width, width, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.size.height, height, accuracy: 0.000_000_001, file: file, line: line)
    }

    func testLayoutFitsAndCentersImageAtMultipleScalesAndViewSizes() throws {
        let fitted = try makeLayout()
        assertRect(fitted.imageRect, x: 0, y: 100, width: 400, height: 200)
        XCTAssertEqual(fitted.imageRect.width / fitted.imageRect.height, 2, accuracy: 0.000_000_001)

        let half = try makeLayout(scale: 0.5)
        assertRect(half.imageRect, x: 100, y: 150, width: 200, height: 100)
        XCTAssertEqual(half.imageRect.width / half.imageRect.height, 2, accuracy: 0.000_000_001)

        let doubled = try makeLayout(scale: 2)
        assertRect(doubled.imageRect, x: -200, y: 0, width: 800, height: 400)
        XCTAssertEqual(doubled.imageRect.width / doubled.imageRect.height, 2, accuracy: 0.000_000_001)

        let tallView = try makeLayout(viewSize: CGSize(width: 300, height: 600))
        assertRect(tallView.imageRect, x: 0, y: 225, width: 300, height: 150)
        XCTAssertEqual(tallView.imageRect.width / tallView.imageRect.height, 2, accuracy: 0.000_000_001)
    }

    func testNormalizedCropMapsToDisplayAndOriginalPixels() throws {
        let layout = try makeLayout(crop: ImageRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4))

        assertRect(layout.cropRect, x: 100, y: 140, width: 200, height: 80)
        assertRect(layout.cropPixelRect, x: 50, y: 20, width: 100, height: 40)
    }

    func testPencilTextAndArrowCoordinatesRoundTripAfterZoomAndCrop() throws {
        let layout = try makeLayout(
            scale: 2,
            crop: ImageRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)
        )
        let pencilPoint = ImagePoint(x: 0.25, y: 0.2)
        let textPoint = ImagePoint(x: 0.75, y: 0.6)
        let arrowStart = ImagePoint(x: 0.1, y: 0.9)
        let arrowEnd = ImagePoint(x: 0.9, y: 0.1)

        assertPoint(layout.displayPoint(forNormalized: pencilPoint), x: 0, y: 80)
        assertPoint(layout.displayPoint(forNormalized: textPoint), x: 400, y: 240)
        assertPoint(layout.displayPoint(forNormalized: arrowStart), x: -120, y: 360)
        assertPoint(layout.displayPoint(forNormalized: arrowEnd), x: 520, y: 40)
        assertPoint(layout.originalPoint(forNormalized: pencilPoint), x: 50, y: 20)
        assertPoint(layout.originalPoint(forDisplay: CGPoint(x: 0, y: 80)) ?? .zero, x: 50, y: 20)

        for point in [pencilPoint, textPoint, arrowStart, arrowEnd] {
            let display = layout.displayPoint(forNormalized: point)
            let roundTrip = try XCTUnwrap(layout.normalizedPoint(forDisplay: display))
            XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.000_000_001)
            XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.000_000_001)
            let original = layout.originalPoint(forNormalized: point)
            let originalRoundTrip = try XCTUnwrap(layout.normalizedPoint(forOriginal: original))
            XCTAssertEqual(originalRoundTrip.x, point.x, accuracy: 0.000_000_001)
            XCTAssertEqual(originalRoundTrip.y, point.y, accuracy: 0.000_000_001)
        }
    }

    func testPointsOutsideOriginalImageAreRejectedInsteadOfClamped() throws {
        let layout = try makeLayout(scale: 2)

        XCTAssertNil(layout.normalizedPoint(forDisplay: CGPoint(x: -201, y: 10)))
        XCTAssertNil(layout.normalizedPoint(forDisplay: CGPoint(x: 601, y: 10)))
        XCTAssertNil(layout.normalizedPoint(forDisplay: CGPoint(x: 0, y: -1)))
        XCTAssertNil(layout.normalizedPoint(forDisplay: CGPoint(x: 0, y: 401)))
        XCTAssertNil(layout.normalizedPoint(forDisplay: CGPoint(x: CGFloat.nan, y: 10)))
        XCTAssertNil(layout.normalizedPoint(forOriginal: CGPoint(x: 201, y: 10)))
        XCTAssertNil(layout.originalPoint(forDisplay: CGPoint(x: 0, y: 401)))
    }

    func testMaximumImageEdgesMapToNormalizedOne() throws {
        let layout = try makeLayout()
        let maximum = try XCTUnwrap(layout.normalizedPoint(
            forDisplay: CGPoint(x: layout.imageRect.maxX, y: layout.imageRect.maxY)
        ))

        XCTAssertEqual(maximum, ImagePoint(x: 1, y: 1))
        assertPoint(
            layout.originalPoint(forDisplay: CGPoint(x: layout.imageRect.maxX, y: layout.imageRect.maxY)) ?? .zero,
            x: 200,
            y: 100
        )
    }

    func testCropDragConversionPreservesImageAspectRatioAndBounds() throws {
        let layout = try makeLayout()
        let crop = try XCTUnwrap(layout.normalizedCrop(
            from: CGPoint(x: 40, y: 300),
            to: CGPoint(x: 240, y: 200)
        ))

        XCTAssertEqual(crop.x, 0.1, accuracy: 0.000_000_001)
        XCTAssertEqual(crop.y, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(crop.width, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(crop.height, 0.5, accuracy: 0.000_000_001)
        let pixelAspect = (crop.width * 200) / (crop.height * 100)
        XCTAssertEqual(pixelAspect, 2, accuracy: 0.000_000_001)

        let clipped = try XCTUnwrap(layout.normalizedCrop(
            from: CGPoint(x: -100, y: 500),
            to: CGPoint(x: 100, y: 200)
        ))
        XCTAssertEqual(clipped.x, 0, accuracy: 0.000_000_001)
        XCTAssertEqual(clipped.y, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(clipped.width, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(clipped.height, 0.5, accuracy: 0.000_000_001)

        let nearEdge = try XCTUnwrap(layout.normalizedCrop(
            from: CGPoint(x: 350, y: 280),
            to: CGPoint(x: 390, y: 240)
        ))
        XCTAssertEqual(nearEdge.x, 0.875, accuracy: 0.000_000_001)
        XCTAssertEqual(nearEdge.y, 0.775, accuracy: 0.000_000_001)
        XCTAssertEqual(nearEdge.width, 0.125, accuracy: 0.000_000_001)
        XCTAssertEqual(nearEdge.height, 0.125, accuracy: 0.000_000_001)
    }

    func testInvalidLayoutInputsProduceNoLayout() {
        XCTAssertNil(ImageRenderer.Layout(
            originalSize: CGSize(width: 0, height: 100),
            displayScale: 1,
            crop: .full,
            viewSize: CGSize(width: 400, height: 400)
        ))
        XCTAssertNil(ImageRenderer.Layout(
            originalSize: CGSize(width: 200, height: 100),
            displayScale: .nan,
            crop: .full,
            viewSize: CGSize(width: 400, height: 400)
        ))
        XCTAssertNil(ImageRenderer.Layout(
            originalSize: CGSize(width: 200, height: 100),
            displayScale: 1,
            crop: ImageRect(x: -0.1, y: 0, width: 1, height: 1),
            viewSize: CGSize(width: 400, height: 400)
        ))
        XCTAssertNil(ImageRenderer.Layout(
            originalSize: CGSize(width: 200, height: 100),
            displayScale: 1,
            crop: .full,
            viewSize: .zero
        ))
    }

    func testCanvasEmitsNormalizedPencilTextAndArrowCallbacks() throws {
        let canvas = try makeCanvas(scale: 2, crop: ImageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let layout = try makeLayout(scale: 2, crop: ImageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        var pencil: [ImagePoint] = []
        var text: (content: String, position: ImagePoint)?
        var arrow: (start: ImagePoint, end: ImagePoint)?
        canvas.onPencil = { pencil = $0 }
        canvas.onText = { text = ($0, $1) }
        canvas.onArrow = { arrow = ($0, $1) }

        canvas.tool = .pencil
        canvas.beginInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.1, y: 0.2)))
        canvas.continueInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.3, y: 0.4)))
        canvas.endInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.5, y: 0.6)))
        XCTAssertEqual(pencil.count, 3)
        XCTAssertEqual(pencil[0].x, 0.1, accuracy: 0.000_000_001)
        XCTAssertEqual(pencil[1].y, 0.4, accuracy: 0.000_000_001)
        XCTAssertEqual(pencil[2], ImagePoint(x: 0.5, y: 0.6))

        canvas.textContent = "hello"
        canvas.tool = .text
        canvas.beginInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.6, y: 0.7)))
        XCTAssertEqual(text?.content, "hello")
        XCTAssertEqual(text?.position.x ?? 0, 0.6, accuracy: 0.000_000_001)
        XCTAssertEqual(text?.position.y ?? 0, 0.7, accuracy: 0.000_000_001)

        canvas.tool = .arrow
        canvas.beginInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.2, y: 0.3)))
        canvas.endInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.8, y: 0.9)))
        XCTAssertEqual(arrow?.start.x ?? 0, 0.2, accuracy: 0.000_000_001)
        XCTAssertEqual(arrow?.start.y ?? 0, 0.3, accuracy: 0.000_000_001)
        XCTAssertEqual(arrow?.end.x ?? 0, 0.8, accuracy: 0.000_000_001)
        XCTAssertEqual(arrow?.end.y ?? 0, 0.9, accuracy: 0.000_000_001)
    }

    func testCanvasRejectsOutOfRangeAnnotationInteractions() throws {
        let canvas = try makeCanvas()
        let layout = try makeLayout()
        var callbackCount = 0
        canvas.onPencil = { _ in callbackCount += 1 }
        canvas.onText = { _, _ in callbackCount += 1 }
        canvas.onArrow = { _, _ in callbackCount += 1 }

        canvas.tool = .pencil
        canvas.beginInteraction(at: CGPoint(x: -1, y: 10))
        canvas.endInteraction(at: CGPoint(x: 20, y: 20))
        canvas.tool = .text
        canvas.beginInteraction(at: CGPoint(x: -1, y: 10))
        canvas.tool = .arrow
        canvas.beginInteraction(at: layout.displayPoint(forNormalized: ImagePoint(x: 0.5, y: 0.5)))
        canvas.endInteraction(at: CGPoint(x: 401, y: 20))

        XCTAssertEqual(callbackCount, 0)
    }

    func testCanvasCreatesMovesAndResizesAspectPreservingCrop() throws {
        let canvas = try makeCanvas()
        var crops: [ImageRect] = []
        canvas.onCrop = { crops.append($0) }
        canvas.isCropEditingEnabled = true

        canvas.beginInteraction(at: CGPoint(x: 40, y: 300))
        canvas.endInteraction(at: CGPoint(x: 240, y: 200))
        let created = try XCTUnwrap(crops.last)
        XCTAssertEqual(created.x, 0.1, accuracy: 0.000_000_001)
        XCTAssertEqual(created.y, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(created.width, 0.5, accuracy: 0.000_000_001)
        XCTAssertEqual(created.height, 0.5, accuracy: 0.000_000_001)

        canvas.document?.cropRect = created
        canvas.beginInteraction(at: CGPoint(x: 140, y: 250))
        canvas.endInteraction(at: CGPoint(x: 160, y: 240))
        let moved = try XCTUnwrap(crops.last)
        XCTAssertEqual(moved.x, 0.15, accuracy: 0.000_000_001)
        XCTAssertEqual(moved.y, 0.45, accuracy: 0.000_000_001)
        XCTAssertEqual(moved.width, created.width, accuracy: 0.000_000_001)
        XCTAssertEqual(moved.height, created.height, accuracy: 0.000_000_001)

        canvas.document?.cropRect = moved
        let layout = try makeLayout(crop: moved)
        canvas.beginInteraction(at: CGPoint(x: layout.cropRect.maxX, y: layout.cropRect.minY))
        canvas.endInteraction(at: CGPoint(x: layout.cropRect.maxX + 40, y: layout.cropRect.minY - 20))
        let resized = try XCTUnwrap(crops.last)
        XCTAssertEqual(resized.x, moved.x, accuracy: 0.000_000_001)
        XCTAssertEqual(resized.width, moved.width + 0.1, accuracy: 0.000_000_001)
        XCTAssertEqual(resized.height, moved.height + 0.1, accuracy: 0.000_000_001)
        let pixelAspect = (resized.width * 200) / (resized.height * 100)
        XCTAssertEqual(pixelAspect, 2, accuracy: 0.000_000_001)
    }

    private func makeCanvas(
        scale: Double = 1,
        crop: ImageRect = .full
    ) throws -> ImageCanvasView {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 200,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let id = UUID().uuidString
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        canvas.image = image
        canvas.document = ImageDocument(
            id: id,
            originalRelativePath: "Images/\(id).png",
            displayScale: scale,
            cropRect: crop
        )
        return canvas
    }
}
