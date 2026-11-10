import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import FloatingWorkspaceCore

@MainActor
final class ImageDocumentTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeDocument(
        id: String = UUID().uuidString,
        path: String? = nil,
        scale: Double = 1,
        crop: ImageRect = .full,
        annotations: [ImageAnnotation] = []
    ) -> ImageDocument {
        ImageDocument(
            id: id,
            originalRelativePath: path ?? "Images/\(id).png",
            displayScale: scale,
            cropRect: crop,
            annotations: annotations,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    private func writeImage(to url: URL, type: UTType) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func assertRect(
        _ actual: ImageRect,
        equals expected: ImageRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_000_001, file: file, line: line)
    }

    func testModelNormalizationClampsScaleCropPointsAndColors() throws {
        let color = RGBAColor(red: 2, green: -1, blue: 0.25, alpha: 1)
        let annotations = [
            ImageAnnotation.pencil(
                points: [ImagePoint(x: -0.5, y: 0.5), ImagePoint(x: 1.5, y: 0.25)],
                color: color,
                width: 2
            ),
            .text(
                content: "  keep this text \n",
                color: color,
                fontSize: 12,
                position: ImagePoint(x: 1.2, y: -0.1)
            ),
            .arrow(
                start: ImagePoint(x: -1, y: 0.2),
                end: ImagePoint(x: 2, y: 0.8),
                color: color,
                width: 3
            )
        ]
        let document = makeDocument(
            scale: 9,
            crop: ImageRect(x: -0.2, y: 0.8, width: 0.5, height: 0.5),
            annotations: annotations
        )

        let normalized = try document.normalized()

        XCTAssertEqual(normalized.displayScale, 4)
        assertRect(normalized.cropRect, equals: ImageRect(x: 0, y: 0.8, width: 0.5, height: 0.2))
        guard case let .pencil(points, pencilColor, width) = normalized.annotations[0] else {
            return XCTFail("Expected pencil annotation")
        }
        XCTAssertEqual(points, [ImagePoint(x: 0, y: 0.5), ImagePoint(x: 1, y: 0.25)])
        XCTAssertEqual(pencilColor, RGBAColor(red: 1, green: 0, blue: 0.25, alpha: 1))
        XCTAssertEqual(width, 2)
        guard case let .text(content, _, fontSize, position) = normalized.annotations[1] else {
            return XCTFail("Expected text annotation")
        }
        XCTAssertEqual(content, "keep this text")
        XCTAssertEqual(fontSize, 12)
        XCTAssertEqual(position, ImagePoint(x: 1, y: 0))
        guard case let .arrow(start, end, _, _) = normalized.annotations[2] else {
            return XCTFail("Expected arrow annotation")
        }
        XCTAssertEqual(start, ImagePoint(x: 0, y: 0.2))
        XCTAssertEqual(end, ImagePoint(x: 1, y: 0.8))

        var smallScale = document
        smallScale.displayScale = 0
        XCTAssertEqual(try smallScale.normalized().displayScale, 0.1)
    }

    func testNonFiniteScalePointColorAndWidthAreRejected() {
        var document = makeDocument()
        document.displayScale = .nan
        XCTAssertThrowsError(try document.normalized())
        XCTAssertThrowsError(try ImagePoint(x: .nan, y: 0).normalized())
        XCTAssertThrowsError(try ImagePoint(x: 0, y: .infinity).normalized())
        XCTAssertThrowsError(try ImageAnnotation.pencil(
            points: [ImagePoint(x: 0, y: 0)],
            color: RGBAColor(red: 1, green: .nan, blue: 0, alpha: 1),
            width: 1
        ).normalized())
        XCTAssertThrowsError(try ImageAnnotation.arrow(
            start: ImagePoint(x: 0, y: 0),
            end: ImagePoint(x: 1, y: 1),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: .infinity),
            width: 1
        ).normalized())
        XCTAssertThrowsError(try ImageAnnotation.pencil(
            points: [ImagePoint(x: 0, y: 0)],
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
            width: .nan
        ).normalized())
    }

    func testNegativeSizesEmptyTextAndEmptyPencilAreRejected() {
        XCTAssertThrowsError(try ImageRect(x: 0, y: 0, width: -0.1, height: 1).normalized())
        XCTAssertThrowsError(try ImageAnnotation.pencil(
            points: [],
            color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
            width: 1
        ).normalized())
        XCTAssertThrowsError(try ImageAnnotation.pencil(
            points: [ImagePoint(x: 0, y: 0)],
            color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
            width: -1
        ).normalized())
        XCTAssertThrowsError(try ImageAnnotation.text(
            content: " \n\t ",
            color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
            fontSize: 12,
            position: ImagePoint(x: 0, y: 0)
        ).normalized())
        XCTAssertThrowsError(try ImageAnnotation.text(
            content: "valid",
            color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
            fontSize: -1,
            position: ImagePoint(x: 0, y: 0)
        ).normalized())
    }

    func testV1AndV2MigrationPreservesContentAndExactOriginalBytes() throws {
        for version in [1, 2] {
            let directory = try temporaryDirectory()
            let file = directory.appendingPathComponent("workspace-v1.json")
            let draft = WebDraft(
                url: "https://example.com/",
                sanitizedBodyHTML: "<p>keep</p>",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
            let legacy = WorkspaceContent(
                schemaVersion: version,
                selectedMode: .blank,
                noteText: "keep note",
                blankTitle: "keep blank",
                blankBackground: RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
                isPinned: false,
                webDrafts: [draft.url: draft]
            )
            let original = try JSONEncoder().encode(legacy)
            try original.write(to: file)
            let store = WorkspaceFileStore(fileURL: file)

            let first = try store.load()
            let backup = try XCTUnwrap(first.migrationBackupURL)
            let second = try store.load()

            XCTAssertEqual(first.content.schemaVersion, 3)
            XCTAssertNil(first.content.imageDocument)
            XCTAssertEqual(first.content.selectedMode, .blank)
            XCTAssertEqual(first.content.noteText, "keep note")
            XCTAssertEqual(first.content.blankTitle, "keep blank")
            XCTAssertEqual(first.content.blankBackground, legacy.blankBackground)
            XCTAssertFalse(first.content.isPinned)
            XCTAssertEqual(first.content.webDrafts, [draft.url: draft])
            XCTAssertEqual(try Data(contentsOf: file), original)
            XCTAssertEqual(try Data(contentsOf: backup), original)
            XCTAssertEqual(second.migrationBackupURL, backup)
            let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("workspace-v1.backup-") }
            XCTAssertEqual(backups.count, 1)
        }
    }

    func testSchemaV3RoundTripAndV2SaveRejection() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let store = WorkspaceFileStore(fileURL: file)
        var content = WorkspaceContent.default
        content.imageDocument = makeDocument()
        XCTAssertEqual(content.schemaVersion, 3)

        try store.save(content)
        XCTAssertEqual(try store.load().content, content)

        let original = try Data(contentsOf: file)
        content.schemaVersion = 2
        XCTAssertThrowsError(try store.save(content))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testPNGAndJPEGImportCopyIntoManagedImagesWithoutTouchingSource() throws {
        for (pathExtension, type) in [("png", UTType.png), ("jpg", .jpeg), ("jpeg", .jpeg)] {
            let directory = try temporaryDirectory()
            let workspace = directory.appendingPathComponent("Workspace")
            let source = directory.appendingPathComponent("source.\(pathExtension)")
            try writeImage(to: source, type: type)
            let sourceBytes = try Data(contentsOf: source)
            let doubles = try ContentStoreTestDoubles()
            let id = UUID()
            let date = Date(timeIntervalSinceReferenceDate: 300)
            let store = ImageDocumentStore(
                store: doubles.store,
                workspaceDirectory: workspace,
                now: { date },
                idGenerator: { id }
            )

            let document = try store.importImage(at: source)

            XCTAssertEqual(document.id, id.uuidString)
            XCTAssertEqual(document.originalRelativePath, "Images/\(id.uuidString).\(pathExtension)")
            XCTAssertEqual(document.displayScale, 1)
            XCTAssertEqual(document.cropRect, .full)
            XCTAssertTrue(document.annotations.isEmpty)
            XCTAssertEqual(document.updatedAt, date)
            let managed = workspace.appendingPathComponent(document.originalRelativePath)
            XCTAssertEqual(try Data(contentsOf: managed), sourceBytes)
            XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
            XCTAssertEqual(doubles.store.content.imageDocument, document)
            XCTAssertTrue(doubles.store.isDirty)
            XCTAssertEqual(doubles.scheduler.delays, [0.3])
            doubles.scheduler.fire()
            XCTAssertEqual(doubles.saver.snapshots.map(\.imageDocument), [document])
        }
    }

    func testSymlinkSourceImportsResolvedBytesAsIndependentRegularFile() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let resolvedSource = directory.appendingPathComponent("resolved.png")
        let sourceLink = directory.appendingPathComponent("source-link.png")
        try writeImage(to: resolvedSource, type: .png)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: resolvedSource)
        let sourceBytes = try Data(contentsOf: resolvedSource)
        let doubles = try ContentStoreTestDoubles()
        let store = ImageDocumentStore(store: doubles.store, workspaceDirectory: workspace)

        let document = try store.importImage(at: sourceLink)

        let managed = workspace.appendingPathComponent(document.originalRelativePath)
        let resources = try managed.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        XCTAssertEqual(resources.isRegularFile, true)
        XCTAssertEqual(resources.isSymbolicLink, false)
        XCTAssertEqual(try Data(contentsOf: managed), sourceBytes)
        try FileManager.default.removeItem(at: resolvedSource)
        XCTAssertEqual(try Data(contentsOf: managed), sourceBytes)
        XCTAssertEqual(doubles.store.content.imageDocument, document)
    }

    func testRejectedReplacementPreservesDocumentSourceAndManagedDirectory() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let originalSource = directory.appendingPathComponent("original.png")
        try writeImage(to: originalSource, type: .png)
        let originalSourceBytes = try Data(contentsOf: originalSource)
        let doubles = try ContentStoreTestDoubles()
        var ids = [UUID(), UUID()]
        let store = ImageDocumentStore(
            store: doubles.store,
            workspaceDirectory: workspace,
            idGenerator: { ids.removeFirst() }
        )
        let existing = try store.importImage(at: originalSource)
        let originalManagedFiles = try FileManager.default.contentsOfDirectory(
            atPath: workspace.appendingPathComponent("Images").path
        )

        let unsupported = directory.appendingPathComponent("unsupported.gif")
        try originalSourceBytes.write(to: unsupported)
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let oversized = directory.appendingPathComponent("oversized.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: oversized.path))
        try handle.truncate(atOffset: UInt64(50 * 1024 * 1024 + 1))
        try handle.close()

        for (source, reason) in [
            (unsupported, "PNG/JPEG"),
            (invalid, "decode"),
            (oversized, "50MB")
        ] {
            XCTAssertThrowsError(try store.replaceImage(at: source), source.lastPathComponent) { error in
                XCTAssertTrue(error.localizedDescription.contains(reason), error.localizedDescription)
            }
            XCTAssertEqual(doubles.store.content.imageDocument, existing)
            XCTAssertEqual(try Data(contentsOf: originalSource), originalSourceBytes)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(
                    atPath: workspace.appendingPathComponent("Images").path
                ),
                originalManagedFiles
            )
        }
        XCTAssertEqual(doubles.scheduler.delays, [0.3])
    }

    func testReplaceCreatesNewDocumentAndKeepsPreviousManagedCopy() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let firstSource = directory.appendingPathComponent("first.png")
        let secondSource = directory.appendingPathComponent("second.jpg")
        try writeImage(to: firstSource, type: .png)
        try writeImage(to: secondSource, type: .jpeg)
        let firstSourceBytes = try Data(contentsOf: firstSource)
        let doubles = try ContentStoreTestDoubles()
        let firstID = UUID()
        let secondID = UUID()
        var ids = [firstID, secondID]
        let store = ImageDocumentStore(
            store: doubles.store,
            workspaceDirectory: workspace,
            idGenerator: { ids.removeFirst() }
        )
        let first = try store.importImage(at: firstSource)
        store.update {
            $0.displayScale = 2
            $0.cropRect = ImageRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        }

        let second = try store.replaceImage(at: secondSource)

        XCTAssertEqual(first.id, firstID.uuidString)
        XCTAssertEqual(second.id, secondID.uuidString)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.displayScale, 1)
        XCTAssertEqual(second.cropRect, .full)
        XCTAssertTrue(second.annotations.isEmpty)
        XCTAssertEqual(doubles.store.content.imageDocument, second)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent(first.originalRelativePath).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent(second.originalRelativePath).path
        ))
        XCTAssertEqual(try Data(contentsOf: firstSource), firstSourceBytes)
    }

    func testDeleteRemovesOnlyManagedCopy() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let source = directory.appendingPathComponent("source.png")
        try writeImage(to: source, type: .png)
        let sourceBytes = try Data(contentsOf: source)
        let doubles = try ContentStoreTestDoubles()
        let store = ImageDocumentStore(store: doubles.store, workspaceDirectory: workspace)
        let document = try store.importImage(at: source)
        let managed = workspace.appendingPathComponent(document.originalRelativePath)

        try store.deleteDocument()

        XCTAssertNil(doubles.store.content.imageDocument)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertEqual(doubles.scheduler.delays, [0.3, 0.3])
        doubles.scheduler.fire()
        XCTAssertNil(doubles.saver.snapshots.last?.imageDocument)
    }

    func testDeleteRejectsAbsoluteTraversalAndOutsideImagesPaths() throws {
        let id = UUID().uuidString
        for pathKind in ["absolute", "traversal", "other-directory"] {
            let directory = try temporaryDirectory()
            let workspace = directory.appendingPathComponent("Workspace")
            let external = directory.appendingPathComponent("outside.png")
            let sentinel = Data("do not touch".utf8)
            try sentinel.write(to: external)
            let other = workspace.appendingPathComponent("Other/\(id).png")
            try FileManager.default.createDirectory(
                at: other.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try sentinel.write(to: other)
            let path: String
            let protectedFile: URL
            switch pathKind {
            case "absolute":
                path = external.path
                protectedFile = external
            case "traversal":
                path = "../outside.png"
                protectedFile = external
            default:
                path = "Other/\(id).png"
                protectedFile = other
            }
            var content = WorkspaceContent.default
            content.imageDocument = makeDocument(id: id, path: path)
            let scheduler = ManualSaveScheduler()
            let saver = ControlledWorkspaceSaver()
            let contentStore = try ContentStore(
                loader: FakeWorkspaceLoader(content: content),
                scheduler: scheduler,
                saver: saver
            )
            let store = ImageDocumentStore(store: contentStore, workspaceDirectory: workspace)

            XCTAssertThrowsError(try store.deleteDocument(), pathKind)

            XCTAssertEqual(contentStore.content, content)
            XCTAssertEqual(try Data(contentsOf: protectedFile), sentinel)
            XCTAssertTrue(scheduler.delays.isEmpty)
            XCTAssertTrue(saver.snapshots.isEmpty)
        }
    }

    func testDeleteRejectsManagedSymlinkEscapingImagesDirectory() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let images = workspace.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let external = directory.appendingPathComponent("outside.png")
        let sentinel = Data("do not touch".utf8)
        try sentinel.write(to: external)
        let id = UUID().uuidString
        try FileManager.default.createSymbolicLink(
            at: images.appendingPathComponent("\(id).png"),
            withDestinationURL: external
        )
        var content = WorkspaceContent.default
        content.imageDocument = makeDocument(id: id)
        let contentStore = try ContentStore(
            loader: FakeWorkspaceLoader(content: content),
            scheduler: ManualSaveScheduler(),
            saver: ControlledWorkspaceSaver()
        )
        let store = ImageDocumentStore(store: contentStore, workspaceDirectory: workspace)

        XCTAssertThrowsError(try store.deleteDocument())

        XCTAssertEqual(contentStore.content, content)
        XCTAssertEqual(try Data(contentsOf: external), sentinel)
    }

    func testDeleteRejectsInternalSymlinkInsteadOfDeletingItsTarget() throws {
        let directory = try temporaryDirectory()
        let workspace = directory.appendingPathComponent("Workspace")
        let images = workspace.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let otherID = UUID().uuidString
        let link = images.appendingPathComponent("\(id).png")
        let other = images.appendingPathComponent("\(otherID).png")
        let sentinel = Data("other managed image".utf8)
        try sentinel.write(to: other)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        var content = WorkspaceContent.default
        content.imageDocument = makeDocument(id: id)
        let scheduler = ManualSaveScheduler()
        let contentStore = try ContentStore(
            loader: FakeWorkspaceLoader(content: content),
            scheduler: scheduler,
            saver: ControlledWorkspaceSaver()
        )
        let store = ImageDocumentStore(store: contentStore, workspaceDirectory: workspace)

        XCTAssertThrowsError(try store.deleteDocument())

        XCTAssertEqual(contentStore.content, content)
        XCTAssertEqual(try Data(contentsOf: other), sentinel)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), other.path)
        XCTAssertTrue(scheduler.delays.isEmpty)
    }

    func testUnsafeImagePathCannotBeSavedOverExistingWorkspaceBytes() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let store = WorkspaceFileStore(fileURL: file)
        try store.save(.default)
        let original = try Data(contentsOf: file)

        for path in ["/tmp/outside.png", "../outside.png", "Other/image.png"] {
            var content = WorkspaceContent.default
            content.imageDocument = makeDocument(path: path)

            XCTAssertThrowsError(try store.save(content), path)
            XCTAssertEqual(try Data(contentsOf: file), original, path)
        }
    }

    func testUpdateWithUnsafeImagePathDoesNotMutateDocument() throws {
        for path in ["/tmp/outside.png", "../outside.png", "Other/image.png"] {
            var content = WorkspaceContent.default
            content.imageDocument = makeDocument(path: path)
            let scheduler = ManualSaveScheduler()
            let contentStore = try ContentStore(
                loader: FakeWorkspaceLoader(content: content),
                scheduler: scheduler,
                saver: ControlledWorkspaceSaver()
            )
            let store = ImageDocumentStore(
                store: contentStore,
                workspaceDirectory: try temporaryDirectory().appendingPathComponent("Workspace")
            )

            store.update { $0.displayScale = 2 }

            XCTAssertEqual(contentStore.content, content, path)
            XCTAssertTrue(scheduler.delays.isEmpty, path)
        }
    }

    func testUpdateNormalizesAndSharesContentStoreSaving() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.png")
        try writeImage(to: source, type: .png)
        let doubles = try ContentStoreTestDoubles()
        var date = Date(timeIntervalSinceReferenceDate: 400)
        let store = ImageDocumentStore(
            store: doubles.store,
            workspaceDirectory: directory.appendingPathComponent("Workspace"),
            now: { date }
        )
        _ = try store.importImage(at: source)
        date = Date(timeIntervalSinceReferenceDate: 500)

        let didUpdate = store.update {
            $0.displayScale = 8
            $0.cropRect = ImageRect(x: 0.9, y: -0.1, width: 0.3, height: 0.4)
            $0.annotations = [
                .text(
                    content: "  normalized  ",
                    color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
                    fontSize: 12,
                    position: ImagePoint(x: 0.2, y: 0.3)
                )
            ]
        }

        XCTAssertTrue(didUpdate)
        let document = try XCTUnwrap(doubles.store.content.imageDocument)
        XCTAssertEqual(document.displayScale, 4)
        assertRect(document.cropRect, equals: ImageRect(x: 0.9, y: 0, width: 0.1, height: 0.4))
        XCTAssertEqual(document.updatedAt, date)
        guard case let .text(content, _, _, _) = document.annotations[0] else {
            return XCTFail("Expected text annotation")
        }
        XCTAssertEqual(content, "normalized")
        XCTAssertEqual(doubles.scheduler.delays, [0.3, 0.3])
        doubles.scheduler.fire()
        XCTAssertEqual(doubles.saver.snapshots.last?.imageDocument, document)
    }

    func testInvalidUpdateDoesNotMutateOrDirtyDocumentAgain() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.png")
        try writeImage(to: source, type: .png)
        let doubles = try ContentStoreTestDoubles()
        let store = ImageDocumentStore(
            store: doubles.store,
            workspaceDirectory: directory.appendingPathComponent("Workspace")
        )
        XCTAssertFalse(store.update { $0.displayScale = 2 })
        let original = try store.importImage(at: source)

        let emptyTextDidUpdate = store.update {
            $0.annotations = [
                .text(
                    content: "  \n ",
                    color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
                    fontSize: 12,
                    position: ImagePoint(x: 0, y: 0)
                )
            ]
        }
        let nonFiniteDidUpdate = store.update { $0.displayScale = .nan }

        XCTAssertFalse(emptyTextDidUpdate)
        XCTAssertFalse(nonFiniteDidUpdate)
        XCTAssertEqual(doubles.store.content.imageDocument, original)
        XCTAssertEqual(doubles.scheduler.delays, [0.3])
    }
}
