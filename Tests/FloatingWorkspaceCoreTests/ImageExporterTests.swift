import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ImageExporterTests: XCTestCase {
    private struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private struct Fixture {
        let root: URL
        let store: ImageDocumentStore
        let document: ImageDocument
        let managedOriginalBytes: Data
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testCropUsesIntegerOriginalPixelsAndPreservesEverySourcePixel() throws {
        let sourcePixels: [Pixel] = (0..<16).map { (index: Int) -> Pixel in
            Pixel(
                red: UInt8(10 + index),
                green: UInt8(40 + index),
                blue: UInt8(80 + index),
                alpha: 255
            )
        }
        let original = try makeImage(width: 4, height: 4, pixels: sourcePixels)
        let fixture = try makeFixture(
            original: original,
            crop: ImageRect(x: 0.26, y: 0.01, width: 0.48, height: 0.48)
        )
        let destination = fixture.root.appendingPathComponent("export.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let exported = try decodeImage(at: destination)
        XCTAssertEqual(exported.width, 2)
        XCTAssertEqual(exported.height, 2)
        let pixels = try rgbaPixels(of: exported)
        let expected = [
            sourcePixels[9], sourcePixels[10],
            sourcePixels[13], sourcePixels[14]
        ]
        XCTAssertEqual(pixels, expected)
        let managedURL = try fixture.store.managedURL(for: fixture.document)
        XCTAssertEqual(try Data(contentsOf: managedURL), fixture.managedOriginalBytes)
    }

    func testDownscaledCanvasAndExportArrowheadsHaveSameOriginalPixelGeometry() throws {
        let transparent = Pixel(red: 0, green: 0, blue: 0, alpha: 0)
        let original = try makeImage(
            width: 400,
            height: 400,
            pixels: Array(repeating: transparent, count: 400 * 400)
        )
        let arrow = ImageAnnotation.arrow(
            start: ImagePoint(x: 0.1, y: 0.5),
            end: ImagePoint(x: 0.9, y: 0.5),
            color: RGBAColor(red: 0, green: 1, blue: 0, alpha: 1),
            width: 2
        )
        let fixture = try makeFixture(original: original, annotations: [arrow])
        let destination = fixture.root.appendingPathComponent("downscaled-arrow.png")
        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.image = original
        canvas.document = fixture.document
        let canvasContext = try makeContext(width: 100, height: 100)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: canvasContext, flipped: false)
        canvas.draw(NSRect(x: 0, y: 0, width: 100, height: 100))
        NSGraphicsContext.restoreGraphicsState()
        let canvasImage = try XCTUnwrap(canvasContext.makeImage())
        let canvasHeadHeight = try arrowHeadHeight(of: canvasImage)
        let exportHeadHeight = try arrowHeadHeight(of: decodeImage(at: destination))

        XCTAssertEqual(
            Double(canvasHeadHeight * 4),
            Double(exportHeadHeight),
            accuracy: 0.51,
            "100-point preview of a 400-pixel original must match export geometry scaled by 0.25"
        )
    }

    func testSinglePointPencilUsesAnnotationColorAtOriginalPixelPosition() throws {
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
        let original = try makeImage(width: 8, height: 8, pixels: Array(repeating: white, count: 64))
        let fixture = try makeFixture(
            original: original,
            annotations: [
                .pencil(
                    points: [ImagePoint(x: 2.5 / 8, y: 2.5 / 8)],
                    color: RGBAColor(red: 0, green: 0, blue: 1, alpha: 1),
                    width: 1
                )
            ]
        )
        let destination = fixture.root.appendingPathComponent("pencil.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let pixels = try rgbaPixels(of: decodeImage(at: destination))
        let dot = pixels[5 * 8 + 2]
        XCTAssertEqual(dot.blue, 255)
        XCTAssertEqual(dot.alpha, 255)
        XCTAssertEqual(dot.red, dot.green)
        XCTAssertLessThan(dot.red, 255, "antialiased blue dot must replace the white background")
        XCTAssertEqual(pixels[2 * 8 + 2], white)
        XCTAssertEqual(pixels[0], white)
    }

    func testArrowShaftAndArrowheadUseAnnotationColor() throws {
        let white = Pixel(red: 255, green: 255, blue: 255, alpha: 255)
        let original = try makeImage(width: 16, height: 16, pixels: Array(repeating: white, count: 256))
        let fixture = try makeFixture(
            original: original,
            annotations: [
                .arrow(
                    start: ImagePoint(x: 1.5 / 16, y: 8.5 / 16),
                    end: ImagePoint(x: 12.5 / 16, y: 8.5 / 16),
                    color: RGBAColor(red: 0, green: 1, blue: 0, alpha: 1),
                    width: 2
                )
            ]
        )
        let destination = fixture.root.appendingPathComponent("arrow.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let pixels = try rgbaPixels(of: decodeImage(at: destination))
        let green = Pixel(red: 0, green: 255, blue: 0, alpha: 255)
        XCTAssertEqual(pixels[7 * 16 + 3], green, "shaft-only pixel outside the arrowhead")
        XCTAssertEqual(pixels[5 * 16 + 6], green, "arrowhead-only pixel")
    }

    func testTextMatchesAttributedStringBottomLeftAnchorInCroppedExportPixels() throws {
        let black = Pixel(red: 0, green: 0, blue: 0, alpha: 255)
        let original = try makeImage(width: 32, height: 24, pixels: Array(repeating: black, count: 32 * 24))
        let color = RGBAColor(red: 1, green: 0, blue: 1, alpha: 1)
        let fixture = try makeFixture(
            original: original,
            crop: ImageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            annotations: [
                .text(
                    content: "A",
                    color: color,
                    fontSize: 12,
                    position: ImagePoint(x: 12.0 / 32, y: 12.0 / 24)
                )
            ]
        )
        let destination = fixture.root.appendingPathComponent("text.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let context = try makeContext(width: 16, height: 12)
        context.translateBy(x: -8, y: -6)
        context.draw(original, in: CGRect(x: 0, y: 0, width: 32, height: 24))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: "A", attributes: attributes).draw(at: CGPoint(x: 12, y: 12))
        NSGraphicsContext.restoreGraphicsState()
        let expected = try XCTUnwrap(context.makeImage())

        XCTAssertEqual(try rgbaPixels(of: decodeImage(at: destination)), try rgbaPixels(of: expected))
    }

    func testExportRetainsExplicitSourceAlpha() throws {
        let original = try makeImage(
            width: 2,
            height: 1,
            pixels: [
                Pixel(red: 255, green: 0, blue: 0, alpha: 255),
                Pixel(red: 0, green: 128, blue: 0, alpha: 128)
            ]
        )
        let fixture = try makeFixture(original: original)
        let destination = fixture.root.appendingPathComponent("alpha.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let exported = try decodeImage(at: destination)
        XCTAssertFalse(
            [.none, .noneSkipFirst, .noneSkipLast].contains(exported.alphaInfo),
            "PNG must retain an alpha channel"
        )
        XCTAssertEqual(try rgbaPixels(of: exported)[1].alpha, 128)
        XCTAssertEqual(try rgbaPixels(of: exported)[1].green, 128)
    }

    func testJPEGOriginalBecomesPNGWithoutChangingManagedBytes() throws {
        let color = Pixel(red: 180, green: 90, blue: 45, alpha: 255)
        let original = try makeImage(width: 4, height: 4, pixels: Array(repeating: color, count: 16))
        let fixture = try makeFixture(original: original, type: .jpeg, pathExtension: "jpg")
        let destination = fixture.root.appendingPathComponent("converted.png")

        try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(exported.width, 4)
        XCTAssertEqual(exported.height, 4)
        let managedURL = try fixture.store.managedURL(for: fixture.document)
        XCTAssertEqual(try Data(contentsOf: managedURL), fixture.managedOriginalBytes)
        XCTAssertNotEqual(try Data(contentsOf: destination), fixture.managedOriginalBytes)
    }

    func testDecodeFailureDoesNotReplaceExistingDestinationBytes() throws {
        let fixture = try makeFixture()
        let destination = fixture.root.appendingPathComponent("existing.png")
        let oldBytes = Data("existing destination bytes".utf8)
        try oldBytes.write(to: destination)
        let managedURL = try fixture.store.managedURL(for: fixture.document)
        try Data("not a decodable image".utf8).write(to: managedURL)

        XCTAssertThrowsError(
            try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)
        )
        XCTAssertEqual(try Data(contentsOf: destination), oldBytes)
    }

    func testCropValidationFailureDoesNotReplaceExistingDestinationBytes() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.store.update { $0.cropRect.width = 0 })
        let document = try XCTUnwrap(fixture.store.document)
        let destination = fixture.root.appendingPathComponent("existing.png")
        let oldBytes = Data("existing destination bytes".utf8)
        try oldBytes.write(to: destination)

        XCTAssertThrowsError(try ImageExporter(store: fixture.store).export(document: document, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), oldBytes)
    }

    func testBitmapContextFailureDoesNotWriteDestination() throws {
        let fixture = try makeFixture()
        let destination = fixture.root.appendingPathComponent("render-failure.png")
        let exporter = ImageExporter(store: fixture.store, renderer: { image, annotations, cropRect in
            try ImageRenderer.render(
                image: image,
                annotations: annotations,
                cropRect: cropRect,
                contextFactory: { _, _, _ in nil }
            )
        })

        XCTAssertThrowsError(try exporter.export(document: fixture.document, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnwritableDestinationFailureDoesNotReplaceExistingBytes() throws {
        if getuid() == 0 {
            throw XCTSkip("POSIX permissions do not reject directory writes for root")
        }
        let fixture = try makeFixture()
        let protectedDirectory = fixture.root.appendingPathComponent("Protected")
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        let destination = protectedDirectory.appendingPathComponent("existing.png")
        let oldBytes = Data("existing destination bytes".utf8)
        try oldBytes.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: protectedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protectedDirectory.path) }

        XCTAssertThrowsError(
            try ImageExporter(store: fixture.store).export(document: fixture.document, to: destination)
        )
        XCTAssertEqual(try Data(contentsOf: destination), oldBytes)
    }

    func testControllerExportsCurrentDocumentToChosenDestination() throws {
        let fixture = try makeFixture()
        let controller = ImageEditController(store: fixture.store)
        let destination = fixture.root.appendingPathComponent("controller-export.png")

        try controller.exportImage(to: destination)

        let exported = try decodeImage(at: destination)
        XCTAssertEqual(exported.width, 2)
        XCTAssertEqual(exported.height, 2)
    }

    func testControllerExportWithoutDocumentThrowsAndDoesNotWriteDestination() throws {
        let fixture = try makeFixture()
        try fixture.store.deleteDocument()
        let controller = ImageEditController(store: fixture.store)
        let destination = fixture.root.appendingPathComponent("missing-document.png")

        XCTAssertThrowsError(try controller.exportImage(to: destination)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("没有可导出的图片"),
                error.localizedDescription
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func makeFixture(
        original: CGImage? = nil,
        type: UTType = .png,
        pathExtension: String = "png",
        crop: ImageRect = .full,
        annotations: [ImageAnnotation] = []
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = root.appendingPathComponent("Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.\(pathExtension)")
        let original = try original ?? makeImage(
            width: 2,
            height: 2,
            pixels: Array(repeating: Pixel(red: 20, green: 40, blue: 60, alpha: 255), count: 4)
        )
        try writeImage(original, to: source, type: type)
        let doubles = try ContentStoreTestDoubles()
        let store = ImageDocumentStore(store: doubles.store, workspaceDirectory: workspace)
        var document = try store.importImage(at: source)
        if crop != .full || !annotations.isEmpty {
            XCTAssertTrue(store.update {
                $0.cropRect = crop
                $0.annotations = annotations
            })
            document = try XCTUnwrap(store.document)
        }
        let managedURL = try store.managedURL(for: document)
        return Fixture(
            root: root,
            store: store,
            document: document,
            managedOriginalBytes: try Data(contentsOf: managedURL)
        )
    }

    private func makeImage(width: Int, height: Int, pixels: [Pixel]) throws -> CGImage {
        XCTAssertEqual(pixels.count, width * height)
        var bytes = pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] }
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            return try XCTUnwrap(context.makeImage())
        }
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
    }

    private func arrowHeadHeight(of image: CGImage) throws -> Int {
        let pixels = try rgbaPixels(of: image)
        let centerRow = image.height / 2
        for row in 0..<centerRow {
            for column in (image.width / 2)..<image.width {
                let pixel = pixels[row * image.width + column]
                let green = Int(pixel.green)
                if green > 100, green > Int(pixel.red) + 50, green > Int(pixel.blue) + 50 {
                    return centerRow - row
                }
            }
        }
        XCTFail("Expected green arrowhead pixels above the shaft")
        return 0
    }

    /// Returns pixels in the bitmap's top-down row order.
    private func rgbaPixels(of image: CGImage) throws -> [Pixel] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return stride(from: 0, to: buffer.count, by: 4).map { index in
                Pixel(
                    red: buffer[index],
                    green: buffer[index + 1],
                    blue: buffer[index + 2],
                    alpha: buffer[index + 3]
                )
            }
        }
    }

    private func writeImage(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func decodeImage(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
