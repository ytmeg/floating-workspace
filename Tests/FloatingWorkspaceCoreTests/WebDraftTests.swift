import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class WebDraftTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("workspace-v1.json")
    }

    func testV1MigrationPreservesContentAndCreatesBackupBeforeNextSave() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        try original.write(to: file)
        let store = WorkspaceFileStore(fileURL: file)
        let result = try store.load()
        XCTAssertEqual(result.content.schemaVersion, 2)
        XCTAssertEqual(result.content.noteText, "keep")
        XCTAssertEqual(result.content.selectedMode, .blank)
        XCTAssertFalse(result.content.isPinned)
        XCTAssertTrue(result.content.webDrafts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let backup = try XCTUnwrap(result.migrationBackupURL)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertNil(result.recoveryURL)
    }

    func testURLNormalizationAndCredentialRejection() throws {
        XCTAssertEqual(try WebDraftKey.normalized(URL(string: "HTTPS://Example.COM:443/a?b=1#frag")!), "https://example.com/a?b=1")
        XCTAssertEqual(try WebDraftKey.normalized(URL(string: "http://example.com:80")!), "http://example.com/")
        XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "https://***********@example.com/private")!))
        XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "file:///tmp/private.html")!))
    }

    func testURLNormalizationPreservesNonDefaultPortPathQueryAndTrailingSlash() throws {
        XCTAssertEqual(
            try WebDraftKey.normalized(URL(string: "HTTPS://Example.COM:8443/a/?b=1#frag")!),
            "https://example.com:8443/a/?b=1"
        )
    }

    func testURLNormalizationRejectsPasswordAndMissingHost() throws {
        XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "https://user:pass@example.com/private")!))
        XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "https:///private")!))
    }

    func testUnsupportedVersionUsesRecoveryPathWithoutSilentlyResetting() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":3,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        try original.write(to: file)

        let result = try WorkspaceFileStore(fileURL: file).load()

        XCTAssertEqual(result.content, .default)
        XCTAssertNil(result.migrationBackupURL)
        let recovery = try XCTUnwrap(result.recoveryURL)
        XCTAssertTrue(recovery.lastPathComponent.hasPrefix("workspace-v1.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: recovery), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMigrationBackupsAreCollisionSafe() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = WorkspaceFileStore(fileURL: file, now: { fixedDate })

        try original.write(to: file)
        let first = try XCTUnwrap(try store.load().migrationBackupURL)
        try original.write(to: file)
        let second = try XCTUnwrap(try store.load().migrationBackupURL)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("workspace-v1.backup-"))
        XCTAssertTrue(second.lastPathComponent.hasPrefix("workspace-v1.backup-"))
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: second), original)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testSaveRejectsSchemaV1() throws {
        var content = WorkspaceContent.default
        content.schemaVersion = 1

        XCTAssertThrowsError(try WorkspaceFileStore(fileURL: try temporaryFile()).save(content))
    }

    func testDraftStoreNormalizesAndSharesContentStoreSaving() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = WebDraft(
            url: "HTTPS://Example.COM:443/a?b=1#frag",
            sanitizedBodyHTML: "<p>edited</p>",
            updatedAt: updatedAt
        )

        try drafts.saveDraft(draft)

        let expected = WebDraft(
            url: "https://example.com/a?b=1",
            sanitizedBodyHTML: "<p>edited</p>",
            updatedAt: updatedAt
        )
        XCTAssertEqual(try drafts.draft(for: URL(string: "https://example.com/a?b=1")!), expected)
        XCTAssertTrue(doubles.store.isDirty)
        XCTAssertEqual(doubles.scheduler.delays, [0.3])
        doubles.scheduler.fire()
        XCTAssertEqual(doubles.saver.snapshots.map(\.webDrafts), [["https://example.com/a?b=1": expected]])
    }

    func testInvalidDraftDoesNotDirtyWorkspace() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let draft = WebDraft(
            url: "file:///tmp/private.html",
            sanitizedBodyHTML: "<p>private</p>",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertThrowsError(try drafts.saveDraft(draft))
        XCTAssertFalse(doubles.store.isDirty)
        XCTAssertTrue(doubles.scheduler.delays.isEmpty)
        XCTAssertTrue(doubles.store.content.webDrafts.isEmpty)
    }
}
