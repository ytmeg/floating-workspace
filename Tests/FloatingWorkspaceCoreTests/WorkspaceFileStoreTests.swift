import XCTest
@testable import FloatingWorkspaceCore

final class WorkspaceFileStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDefaultContentAndAtomicRoundTrip() throws {
        let file = try temporaryDirectory().appendingPathComponent("nested/workspace-v1.json")
        let store = WorkspaceFileStore(fileURL: file)
        let initial = try store.load()
        XCTAssertEqual(initial.content, .default)
        XCTAssertNil(initial.recoveryURL)

        var expected = WorkspaceContent.default
        expected.noteText = "浮窗正文"
        expected.selectedMode = .blank
        expected.blankTitle = "参考"
        expected.isPinned = false
        try store.save(expected)
        let loaded = try store.load()
        XCTAssertEqual(loaded.content, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptJSONIsMovedToTimestampedBackup() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let invalid = Data("not-json".utf8)
        try invalid.write(to: file)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = WorkspaceFileStore(fileURL: file, now: { fixedDate })

        let loaded = try store.load()
        XCTAssertEqual(loaded.content, .default)
        let backup = try XCTUnwrap(loaded.recoveryURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("workspace-v1.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: backup), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTwoCorruptLoadsAtSameTimestampPreserveBothOriginals() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = WorkspaceFileStore(fileURL: file, now: { fixedDate })
        let first = Data("first-corrupt".utf8)
        let second = Data("second-corrupt".utf8)

        try first.write(to: file)
        let firstBackup = try XCTUnwrap(try store.load().recoveryURL)
        try second.write(to: file)
        let secondBackup = try XCTUnwrap(try store.load().recoveryURL)

        XCTAssertNotEqual(firstBackup, secondBackup)
        XCTAssertTrue(secondBackup.lastPathComponent.hasPrefix("workspace-v1.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: firstBackup), first)
        XCTAssertEqual(try Data(contentsOf: secondBackup), second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMalformedV3ImageDocumentUsesCorruptRecoveryAndLaterSavesSucceed() throws {
        let id = UUID().uuidString
        let validPath = "\"originalRelativePath\": \"Images/\(id).png\""
        let cases: [(String, String)] = [
            ("bad id", "\"id\": \"not-a-uuid\", \"originalRelativePath\": \"Images/not-a-uuid.png\""),
            ("escaping path", "\"id\": \"\(id)\", \"originalRelativePath\": \"../\(id).png\""),
            ("invalid annotation", "\"id\": \"\(id)\", \(validPath)")
        ]
        for (name, identity) in cases {
            let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
            let annotations = name == "invalid annotation"
                ? "[{\"text\": {\"content\": \"   \", \"color\": {\"red\": 1, \"green\": 0, \"blue\": 0, \"alpha\": 1}, \"fontSize\": 16, \"position\": {\"x\": 0.5, \"y\": 0.5}}}]"
                : "[]"
            let original = Data("""
                {
                  "schemaVersion": 3,
                  "selectedMode": "image",
                  "noteText": "hand edited",
                  "blankTitle": "空白窗口",
                  "blankBackground": {"red": 0.96, "green": 0.97, "blue": 0.98, "alpha": 1},
                  "isPinned": true,
                  "webDrafts": {},
                  "imageDocument": {
                    \(identity),
                    "displayScale": 1,
                    "cropRect": {"x": 0, "y": 0, "width": 1, "height": 1},
                    "annotations": \(annotations),
                    "updatedAt": 100
                  }
                }
                """.utf8)
            try original.write(to: file)
            let store = WorkspaceFileStore(fileURL: file)

            let loaded = try store.load()

            XCTAssertEqual(loaded.content, .default, name)
            let backup = try XCTUnwrap(loaded.recoveryURL, name)
            XCTAssertTrue(backup.lastPathComponent.hasPrefix("workspace-v1.corrupt-"), name)
            XCTAssertEqual(try Data(contentsOf: backup), original, name)

            var edited = loaded.content
            edited.noteText = "saved after recovery"
            XCTAssertNoThrow(try store.save(edited), name)
            XCTAssertEqual(try store.load().content.noteText, "saved after recovery", name)
            XCTAssertNil(try store.load().recoveryURL, name)
        }
    }

    func testRecoverableV3ImageDocumentValuesAreNormalizedOnLoad() throws {
        let file = try temporaryDirectory().appendingPathComponent("workspace-v1.json")
        let id = UUID().uuidString
        var content = WorkspaceContent.default
        content.imageDocument = ImageDocument(
            id: id,
            originalRelativePath: "Images/\(id).png",
            displayScale: 9,
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let encoder = JSONEncoder()
        try encoder.encode(content).write(to: file)

        let loaded = try WorkspaceFileStore(fileURL: file).load()

        XCTAssertNil(loaded.recoveryURL)
        XCTAssertEqual(loaded.content.imageDocument?.displayScale, 4)
        XCTAssertEqual(loaded.content.imageDocument?.id, id)
    }

    func testAllFourWorkspaceModesAreEnabled() {
        XCTAssertTrue(WorkspaceMode.note.isEnabledInPhase1)
        XCTAssertTrue(WorkspaceMode.blank.isEnabledInPhase1)
        XCTAssertTrue(WorkspaceMode.web.isEnabledInPhase1)
        XCTAssertTrue(WorkspaceMode.image.isEnabledInPhase1)
    }
}
