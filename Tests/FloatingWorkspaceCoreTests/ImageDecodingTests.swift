import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ImageDecodingTests: XCTestCase {
    private struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private static let fixtureDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/images", isDirectory: true)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testOrientationSixFixtureDecodesUprightForImportCanvasAndExport() throws {
        let source = Self.fixtureDirectory.appendingPathComponent("rotated-orientation-6.jpg")
        let fixture = try makeStores()
        _ = try fixture.documentStore.importImage(at: source)
        let document = try XCTUnwrap(fixture.documentStore.document)

        let controller = ImageEditController(store: fixture.documentStore)
        controller.loadViewIfNeeded()
        let canvasImage = try XCTUnwrap(controller.canvasView.image)
        XCTAssertEqual(canvasImage.width, 16)
        XCTAssertEqual(canvasImage.height, 12)
        try assertUprightQuadrants(canvasImage)

        let destination = fixture.root.appendingPathComponent("export.png")
        try ImageExporter(store: fixture.documentStore).export(document: document, to: destination)
        let exported = try decodeRaw(at: destination)
        XCTAssertEqual(exported.width, 16)
        XCTAssertEqual(exported.height, 12)
        try assertUprightQuadrants(exported)
        XCTAssertEqual(
            try Data(contentsOf: fixture.workspace.appendingPathComponent(document.originalRelativePath)),
            try Data(contentsOf: source)
        )
    }

    func testOrientationEightDecodesUpright() throws {
        let root = try temporaryDirectory()
        // Stored pixels are the upright image rotated clockwise; orientation 8 rotates them back.
        let stored = try makeQuadrantImage(
            width: 12,
            height: 16,
            topLeft: RGB(red: 0, green: 0, blue: 255),
            topRight: RGB(red: 255, green: 0, blue: 0),
            bottomLeft: RGB(red: 255, green: 255, blue: 0),
            bottomRight: RGB(red: 0, green: 255, blue: 0)
        )
        let url = root.appendingPathComponent("orientation-8.jpg")
        try writeJPEG(stored, to: url, orientation: 8)

        let image = try ImageDecoding.decodeImage(at: url)

        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 12)
        try assertUprightQuadrants(image)
    }

    func testHeaderOnlyOversizedPNGsAreRejectedBeforeDecodeWithoutMutation() throws {
        for (width, height) in [(20_000, 20_000), (10_001, 10_000), (16_385, 2)] {
            let fixture = try makeStores()
            let source = fixture.root.appendingPathComponent("huge-\(width)x\(height).png")
            try headerOnlyPNG(width: width, height: height).write(to: source)
            let probe = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(probe, 0, nil) as? [CFString: Any],
                "ImageIO must expose the fake header so the cap, not decode failure, rejects it"
            )
            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, width)
            let original = fixture.contentStore.content

            XCTAssertThrowsError(try ImageDecoding.decodeImage(at: source)) { error in
                Self.assertTooLarge(error, width: width, height: height)
            }
            XCTAssertThrowsError(try fixture.documentStore.importImage(at: source)) { error in
                Self.assertTooLarge(error, width: width, height: height)
            }

            XCTAssertEqual(fixture.contentStore.content, original)
            XCTAssertFalse(fixture.contentStore.isDirty)
            XCTAssertTrue(fixture.scheduler.delays.isEmpty)
            XCTAssertEqual(try managedFiles(in: fixture.workspace), [])
        }
    }

    func testRealPixelsOverSideLimitAreRejectedButLimitItselfIsAccepted() throws {
        let fixture = try makeStores()
        let over = fixture.root.appendingPathComponent("over.png")
        let atLimit = fixture.root.appendingPathComponent("limit.png")
        try writePNG(try makeSolidImage(width: 16_385, height: 1), to: over)
        try writePNG(try makeSolidImage(width: 16_384, height: 1), to: atLimit)

        XCTAssertThrowsError(try fixture.documentStore.importImage(at: over)) { error in
            Self.assertTooLarge(error, width: 16_385, height: 1)
        }
        XCTAssertNil(fixture.documentStore.document)

        let document = try fixture.documentStore.importImage(at: atLimit)
        XCTAssertEqual(fixture.documentStore.document, document)
        let image = try ImageDecoding.decodeImage(
            at: try fixture.documentStore.managedURL(for: document)
        )
        XCTAssertEqual(image.width, 16_384)
        XCTAssertEqual(image.height, 1)
    }

    func testExistingManagedOversizedDocumentShowsReasonInCanvasAndExportWithoutMutation() throws {
        let fixture = try makeStores()
        let id = UUID().uuidString
        let document = ImageDocument(
            id: id,
            originalRelativePath: "Images/\(id).png",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let managed = fixture.workspace.appendingPathComponent(document.originalRelativePath)
        try FileManager.default.createDirectory(
            at: managed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try headerOnlyPNG(width: 20_000, height: 20_000).write(to: managed)
        let managedBytes = try Data(contentsOf: managed)
        let loaded = try makeStores(document: document, workspace: fixture.workspace)
        let original = loaded.contentStore.content

        let controller = ImageEditController(store: loaded.documentStore)
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.canvasView.image)
        XCTAssertTrue(controller.errorLabel.stringValue.contains("20000×20000"), controller.errorLabel.stringValue)
        let destination = fixture.root.appendingPathComponent("export.png")
        XCTAssertThrowsError(try controller.exportImage(to: destination)) { error in
            Self.assertTooLarge(error, width: 20_000, height: 20_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(loaded.contentStore.content, original)
        XCTAssertTrue(loaded.scheduler.delays.isEmpty)
        XCTAssertEqual(try Data(contentsOf: managed), managedBytes)
    }

    // MARK: - Helpers

    private struct Stores {
        let root: URL
        let workspace: URL
        let contentStore: ContentStore
        let documentStore: ImageDocumentStore
        let scheduler: ManualSaveScheduler
    }

    private func makeStores(document: ImageDocument? = nil, workspace: URL? = nil) throws -> Stores {
        let root: URL
        if let workspace {
            root = workspace.deletingLastPathComponent()
        } else {
            root = try temporaryDirectory()
        }
        let workspaceURL = workspace ?? root.appendingPathComponent("Workspace")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        var content = WorkspaceContent.default
        content.imageDocument = document
        let scheduler = ManualSaveScheduler()
        let contentStore = try ContentStore(
            loader: FakeWorkspaceLoader(content: content),
            scheduler: scheduler,
            saver: ControlledWorkspaceSaver()
        )
        return Stores(
            root: root,
            workspace: workspaceURL,
            contentStore: contentStore,
            documentStore: ImageDocumentStore(store: contentStore, workspaceDirectory: workspaceURL),
            scheduler: scheduler
        )
    }

    private static func assertTooLarge(
        _ error: Error,
        width: Int,
        height: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, "ImageDecoding", file: file, line: line)
        XCTAssertEqual(nsError.code, 3, file: file, line: line)
        XCTAssertTrue(
            nsError.localizedDescription.contains("\(width)×\(height)"),
            nsError.localizedDescription,
            file: file,
            line: line
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func managedFiles(in workspace: URL) throws -> [String] {
        let images = workspace.appendingPathComponent("Images")
        guard FileManager.default.fileExists(atPath: images.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: images.path)
    }

    /// A PNG whose IHDR declares the given size but which carries no real pixel data.
    /// ImageIO only reports header dimensions once the file is plausibly large, so an
    /// ancillary padding chunk supplies bytes without supplying any decodable rows.
    private func headerOnlyPNG(width: Int, height: Int) -> Data {
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += pngChunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 6, 0, 0, 0])
        png += pngChunk("prIv", [UInt8](repeating: 0, count: width * height * 4 / 1_000 + 1_024))
        png += pngChunk("IDAT", [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])
        png += pngChunk("IEND", [])
        return Data(png)
    }

    private func pngChunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typeBytes = Array(type.utf8)
        return bigEndian(UInt32(data.count)) + typeBytes + data + bigEndian(crc32(typeBytes + data))
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
            }
        }
        return ~crc
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeQuadrantImage(
        width: Int,
        height: Int,
        topLeft: RGB,
        topRight: RGB,
        bottomLeft: RGB,
        bottomRight: RGB
    ) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        for (color, rect) in [
            (topLeft, CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)),
            (topRight, CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)),
            (bottomLeft, CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)),
            (bottomRight, CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight))
        ] {
            context.setFillColor(CGColor(
                srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            ))
            context.fill(rect)
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeJPEG(_ image: CGImage, to url: URL, orientation: Int) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: orientation]
        ] as [CFString: Any] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func decodeRaw(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Upright fixture layout: top-left red, top-right green, bottom-left blue, bottom-right yellow.
    private func assertUprightQuadrants(
        _ image: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = try makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        // Bitmap memory row 0 is the visual top row.
        let samples: [(String, Int, Int, RGB)] = [
            ("top-left", image.width / 4, image.height / 4, RGB(red: 255, green: 0, blue: 0)),
            ("top-right", image.width * 3 / 4, image.height / 4, RGB(red: 0, green: 255, blue: 0)),
            ("bottom-left", image.width / 4, image.height * 3 / 4, RGB(red: 0, green: 0, blue: 255)),
            ("bottom-right", image.width * 3 / 4, image.height * 3 / 4, RGB(red: 255, green: 255, blue: 0))
        ]
        for (name, x, row, expected) in samples {
            let offset = (row * image.width + x) * 4
            let actual = RGB(red: Int(data[offset]), green: Int(data[offset + 1]), blue: Int(data[offset + 2]))
            for (channel, value, want) in [
                ("red", actual.red, expected.red),
                ("green", actual.green, expected.green),
                ("blue", actual.blue, expected.blue)
            ] {
                XCTAssertEqual(
                    value,
                    want,
                    accuracy: 8,
                    "\(name) \(channel): got \(actual)",
                    file: file,
                    line: line
                )
            }
        }
    }
}
