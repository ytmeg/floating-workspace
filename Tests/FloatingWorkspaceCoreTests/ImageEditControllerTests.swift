import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class ImageEditControllerTests: XCTestCase {
    private struct Fixture {
        let controller: ImageEditController
        let documentStore: ImageDocumentStore
        let contentStore: ContentStore
        let scheduler: ManualSaveScheduler
        let saver: ControlledWorkspaceSaver
        let workspace: URL
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testImportReplaceDeleteUseDocumentStoreAndSharedPersistence() throws {
        let fixture = try makeFixture()
        let sourceDirectory = fixture.workspace.deletingLastPathComponent()
        let firstSource = sourceDirectory.appendingPathComponent("first.png")
        let secondSource = sourceDirectory.appendingPathComponent("second.png")
        try writeImage(to: firstSource)
        try writeImage(to: secondSource)

        try fixture.controller.importImage(at: firstSource)
        let first = try XCTUnwrap(fixture.contentStore.content.imageDocument)
        let firstManaged = fixture.workspace.appendingPathComponent(first.originalRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstManaged.path))
        XCTAssertNotNil(fixture.controller.canvasView.image)

        try fixture.controller.replaceImage(at: secondSource)
        let second = try XCTUnwrap(fixture.contentStore.content.imageDocument)
        let secondManaged = fixture.workspace.appendingPathComponent(second.originalRelativePath)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstManaged.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondManaged.path))

        try fixture.controller.deleteImage()

        XCTAssertNil(fixture.contentStore.content.imageDocument)
        XCTAssertNil(fixture.controller.canvasView.image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstManaged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondManaged.path))
        XCTAssertEqual(fixture.scheduler.delays, [0.3, 0.3, 0.3])
        fixture.scheduler.fire()
        XCTAssertNil(fixture.saver.snapshots.last?.imageDocument)
    }

    func testZoomSliderAndCropActionsUpdateThroughStore() throws {
        let fixture = try makeFixture(document: makeDocument())
        let controller = fixture.controller

        controller.zoomSlider.doubleValue = 2.5
        controller.zoomChanged()
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.displayScale, 2.5)
        XCTAssertTrue(controller.setDisplayScale(9))
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.displayScale, 4)

        controller.toggleCrop()
        XCTAssertTrue(controller.isCropEditing)
        XCTAssertTrue(controller.canvasView.isCropEditingEnabled)
        let crop = ImageRect(x: 0.1, y: 0.2, width: 0.6, height: 0.6)
        XCTAssertTrue(controller.updateCrop(crop))
        assertRect(fixture.contentStore.content.imageDocument?.cropRect, equals: crop)

        controller.resetCrop()
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.cropRect, .full)
        XCTAssertEqual(fixture.scheduler.delays, [0.3, 0.3, 0.3, 0.3])
        fixture.scheduler.fire()
        XCTAssertEqual(fixture.saver.snapshots.last?.imageDocument?.cropRect, .full)
        XCTAssertEqual(fixture.saver.snapshots.last?.imageDocument?.displayScale, 4)
    }

    func testPencilTextAndArrowPersistNormalizedCoordinatesAfterZoomAndCrop() throws {
        let crop = ImageRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let fixture = try makeFixture(document: makeDocument(scale: 2, crop: crop))
        let color = RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)

        XCTAssertTrue(fixture.controller.addPencil(
            points: [ImagePoint(x: 0.25, y: 0.25), ImagePoint(x: 0.75, y: 0.75)],
            color: color,
            width: 3
        ))
        XCTAssertTrue(fixture.controller.addText(
            "  cropped note  ",
            at: ImagePoint(x: 0.5, y: 0.5),
            color: color,
            fontSize: 18
        ))
        XCTAssertTrue(fixture.controller.addArrow(
            from: ImagePoint(x: 0.25, y: 0.75),
            to: ImagePoint(x: 0.75, y: 0.25),
            color: color,
            width: 4
        ))

        let document = try XCTUnwrap(fixture.contentStore.content.imageDocument)
        XCTAssertEqual(document.displayScale, 2)
        XCTAssertEqual(document.cropRect, crop)
        XCTAssertEqual(document.annotations.count, 3)
        guard case let .pencil(points, pencilColor, pencilWidth) = document.annotations[0] else {
            return XCTFail("Expected pencil annotation")
        }
        XCTAssertEqual(points, [ImagePoint(x: 0.25, y: 0.25), ImagePoint(x: 0.75, y: 0.75)])
        XCTAssertEqual(pencilColor, color)
        XCTAssertEqual(pencilWidth, 3)
        guard case let .text(content, textColor, fontSize, position) = document.annotations[1] else {
            return XCTFail("Expected text annotation")
        }
        XCTAssertEqual(content, "cropped note")
        XCTAssertEqual(textColor, color)
        XCTAssertEqual(fontSize, 18)
        XCTAssertEqual(position, ImagePoint(x: 0.5, y: 0.5))
        guard case let .arrow(start, end, arrowColor, arrowWidth) = document.annotations[2] else {
            return XCTFail("Expected arrow annotation")
        }
        XCTAssertEqual(start, ImagePoint(x: 0.25, y: 0.75))
        XCTAssertEqual(end, ImagePoint(x: 0.75, y: 0.25))
        XCTAssertEqual(arrowColor, color)
        XCTAssertEqual(arrowWidth, 4)
        fixture.scheduler.fire()
        XCTAssertEqual(fixture.saver.snapshots.last?.imageDocument?.annotations, document.annotations)
    }

    func testToolSelectionAndColorWellApplyToNextAnnotation() throws {
        let fixture = try makeFixture(document: makeDocument())
        let controller = fixture.controller

        controller.selectTool(.text)
        controller.colorWell.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        controller.colorChanged()
        XCTAssertTrue(controller.addText("color", at: ImagePoint(x: 0.2, y: 0.3)))

        XCTAssertEqual(controller.selectedTool, .text)
        XCTAssertEqual(controller.canvasView.tool, .text)
        XCTAssertEqual(controller.textButton.state, .on)
        XCTAssertEqual(controller.pencilButton.state, .off)
        let annotation = try XCTUnwrap(fixture.contentStore.content.imageDocument?.annotations.last)
        guard case let .text(_, color, _, _) = annotation else {
            return XCTFail("Expected text annotation")
        }
        XCTAssertEqual(color.red, 0.2, accuracy: 0.000_000_001)
        XCTAssertEqual(color.green, 0.4, accuracy: 0.000_000_001)
        XCTAssertEqual(color.blue, 0.6, accuracy: 0.000_000_001)
        XCTAssertEqual(color.alpha, 0.8, accuracy: 0.000_000_001)
    }

    func testEmptyTextAndOutOfRangePointsDoNotMutateOrScheduleSave() throws {
        let fixture = try makeFixture(document: makeDocument())
        let original = fixture.contentStore.content
        let color = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

        XCTAssertFalse(fixture.controller.addText(" \n\t ", at: ImagePoint(x: 0.5, y: 0.5)))
        XCTAssertFalse(fixture.controller.addText("outside", at: ImagePoint(x: 1.1, y: 0.5)))
        XCTAssertFalse(fixture.controller.addPencil(points: [], color: color, width: 2))
        XCTAssertFalse(fixture.controller.addPencil(
            points: [ImagePoint(x: -0.1, y: 0.5)],
            color: color,
            width: 2
        ))
        XCTAssertFalse(fixture.controller.addArrow(
            from: ImagePoint(x: 0.2, y: 0.2),
            to: ImagePoint(x: 0.8, y: 1.2),
            color: color,
            width: 2
        ))
        XCTAssertFalse(fixture.controller.addPencil(
            points: [ImagePoint(x: .nan, y: 0.5)],
            color: color,
            width: 2
        ))

        XCTAssertEqual(fixture.contentStore.content, original)
        XCTAssertTrue(fixture.scheduler.delays.isEmpty)
        XCTAssertTrue(fixture.saver.snapshots.isEmpty)
    }

    func testInvalidScaleAndCropDoNotMutateOrScheduleSave() throws {
        let fixture = try makeFixture(document: makeDocument())
        let original = fixture.contentStore.content

        XCTAssertFalse(fixture.controller.setDisplayScale(.nan))
        XCTAssertFalse(fixture.controller.updateCrop(ImageRect(x: -0.1, y: 0, width: 0.5, height: 0.5)))
        XCTAssertFalse(fixture.controller.updateCrop(ImageRect(x: 0.8, y: 0, width: 0.3, height: 0.3)))
        XCTAssertFalse(fixture.controller.updateCrop(ImageRect(x: 0, y: 0, width: 0, height: 0.5)))
        XCTAssertFalse(fixture.controller.updateCrop(ImageRect(x: 0.1, y: 0.1, width: 0.5, height: 0.4)))

        XCTAssertEqual(fixture.contentStore.content, original)
        XCTAssertTrue(fixture.scheduler.delays.isEmpty)
        XCTAssertTrue(fixture.saver.snapshots.isEmpty)
    }

    func testUndoRemovesLastAndClearRemovesAllWithoutEmptyNoOpSaves() throws {
        let fixture = try makeFixture(document: makeDocument())
        let controller = fixture.controller
        XCTAssertTrue(controller.addPencil(points: [ImagePoint(x: 0.1, y: 0.1)]))
        XCTAssertTrue(controller.addText("second", at: ImagePoint(x: 0.2, y: 0.2)))
        XCTAssertTrue(controller.addArrow(from: ImagePoint(x: 0.1, y: 0.2), to: ImagePoint(x: 0.3, y: 0.4)))

        controller.undoAnnotation()
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.annotations.count, 2)
        guard case .text? = fixture.contentStore.content.imageDocument?.annotations.last else {
            return XCTFail("Undo must remove only the last arrow")
        }
        controller.undoAnnotation()
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.annotations.count, 1)
        controller.clearAnnotations()
        XCTAssertEqual(fixture.contentStore.content.imageDocument?.annotations, [])
        let delaysAfterClear = fixture.scheduler.delays.count

        controller.clearAnnotations()
        controller.undoAnnotation()

        XCTAssertEqual(fixture.scheduler.delays.count, delaysAfterClear)
        fixture.scheduler.fire()
        XCTAssertEqual(fixture.saver.snapshots.last?.imageDocument?.annotations, [])
    }

    func testExportActionPassesCurrentDocumentWithoutASecondSavePath() throws {
        let fixture = try makeFixture(document: makeDocument())
        var exported: ImageDocument?
        fixture.controller.onExport = { exported = $0 }
        let original = fixture.contentStore.content

        fixture.controller.exportButton.performClick(nil)

        XCTAssertEqual(exported, original.imageDocument)
        XCTAssertEqual(fixture.contentStore.content, original)
        XCTAssertTrue(fixture.scheduler.delays.isEmpty)
        XCTAssertTrue(fixture.saver.snapshots.isEmpty)
    }

    func testToolbarContainsAndWiresRequiredEditingControls() throws {
        let fixture = try makeFixture(document: makeDocument())
        let controller = fixture.controller
        let controls: [NSView] = [
            controller.importButton,
            controller.replaceButton,
            controller.deleteButton,
            controller.zoomSlider,
            controller.cropButton,
            controller.resetCropButton,
            controller.pencilButton,
            controller.textButton,
            controller.arrowButton,
            controller.colorWell,
            controller.undoButton,
            controller.clearButton,
            controller.exportButton
        ]

        for control in controls {
            XCTAssertNotNil(control.superview, control.accessibilityIdentifier())
        }
        XCTAssertEqual(controller.zoomSlider.minValue, 0.1)
        XCTAssertEqual(controller.zoomSlider.maxValue, 4)
        XCTAssertTrue(controller.zoomSlider.target === controller)
        XCTAssertTrue(controller.colorWell.target === controller)
        XCTAssertTrue(controller.cropButton.target === controller)
        XCTAssertTrue(controller.exportButton.target === controller)
        XCTAssertEqual(controller.canvasView.superview, controller.view)
    }

    private func makeFixture(document: ImageDocument? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = root.appendingPathComponent("Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        if let document {
            try writeImage(to: workspace.appendingPathComponent(document.originalRelativePath))
        }
        var content = WorkspaceContent.default
        content.imageDocument = document
        let scheduler = ManualSaveScheduler()
        let saver = ControlledWorkspaceSaver()
        let contentStore = try ContentStore(
            loader: FakeWorkspaceLoader(content: content),
            scheduler: scheduler,
            saver: saver
        )
        let documentStore = ImageDocumentStore(
            store: contentStore,
            workspaceDirectory: workspace,
            now: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )
        let controller = ImageEditController(store: documentStore)
        controller.loadViewIfNeeded()
        return Fixture(
            controller: controller,
            documentStore: documentStore,
            contentStore: contentStore,
            scheduler: scheduler,
            saver: saver,
            workspace: workspace
        )
    }

    private func makeDocument(
        scale: Double = 1,
        crop: ImageRect = .full,
        annotations: [ImageAnnotation] = []
    ) -> ImageDocument {
        let id = UUID().uuidString
        return ImageDocument(
            id: id,
            originalRelativePath: "Images/\(id).png",
            displayScale: scale,
            cropRect: crop,
            annotations: annotations,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    private func writeImage(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 200,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func assertRect(
        _ actual: ImageRect?,
        equals expected: ImageRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            return XCTFail("Expected crop rect", file: file, line: line)
        }
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_000_001, file: file, line: line)
    }
}
