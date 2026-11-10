import XCTest
import FloatingWorkspaceCore

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
        XCTAssertEqual(result.content.schemaVersion, 3)
        XCTAssertEqual(result.content.noteText, "keep")
        XCTAssertEqual(result.content.selectedMode, .blank)
        XCTAssertFalse(result.content.isPinned)
        XCTAssertTrue(result.content.webDrafts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let backup = try XCTUnwrap(result.migrationBackupURL)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertNil(result.recoveryURL)
    }

    func testMigrationBackupUsesBytesReadAndNeverOverwritesExistingDestination() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"original\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        let replacement = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"replacement\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        try original.write(to: file)
        let existing = file.deletingLastPathComponent().appendingPathComponent("workspace-v1.backup-2023-11-14T22-13-20.000Z.json")
        let sentinel = Data("existing-backup".utf8)
        try sentinel.write(to: existing)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        var didReplace = false
        var replacementError: Error?
        let store = WorkspaceFileStore(fileURL: file, now: {
            if !didReplace {
                didReplace = true
                do {
                    try replacement.write(to: file)
                } catch {
                    replacementError = error
                }
            }
            return fixedDate
        })

        let result = try store.load()

        XCTAssertNil(replacementError)
        XCTAssertEqual(result.content.schemaVersion, 3)
        XCTAssertEqual(result.content.noteText, "original")
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        let backup = try XCTUnwrap(result.migrationBackupURL)
        XCTAssertTrue(backup.lastPathComponent.hasSuffix("-2.json"))
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: file), replacement)
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

    func testURLNormalizationRejectsMalformedAuthoritiesWithoutMutatingURL() throws {
        let invalid = [
            "https://example.com:99999/private",
            "https://example..com/private",
            "https://-example.com/private"
        ]
        for raw in invalid {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertThrowsError(try WebDraftKey.normalized(url), raw)
            XCTAssertEqual(url.absoluteString, raw)
        }
    }

    func testURLNormalizationRejectsPasswordWithoutLeakingItAndRejectsMissingHost() throws {
        let password = "s3cr3t"
        let url = try XCTUnwrap(URL(string: "https://user:\(password)@example.com/private"))
        XCTAssertThrowsError(try WebDraftKey.normalized(url)) { error in
            XCTAssertFalse(error.localizedDescription.contains(password))
        }
        XCTAssertThrowsError(try WebDraftKey.normalized(URL(string: "https:///private")!))
    }

    func testNullWebDraftsEnterCorruptRecoveryInsteadOfBecomingEmpty() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":2,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false,\"webDrafts\":null}".utf8)
        try original.write(to: file)

        let result = try WorkspaceFileStore(fileURL: file).load()

        XCTAssertEqual(result.content, .default)
        XCTAssertNil(result.migrationBackupURL)
        let recovery = try XCTUnwrap(result.recoveryURL)
        XCTAssertEqual(try Data(contentsOf: recovery), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUnsupportedVersionUsesRecoveryPathWithoutSilentlyResetting() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":4,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        try original.write(to: file)

        let result = try WorkspaceFileStore(fileURL: file).load()

        XCTAssertEqual(result.content, .default)
        XCTAssertNil(result.migrationBackupURL)
        let recovery = try XCTUnwrap(result.recoveryURL)
        XCTAssertTrue(recovery.lastPathComponent.hasPrefix("workspace-v1.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: recovery), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRepeatedMigrationReusesByteIdenticalBackupWithoutStartupWrites() throws {
        let file = try temporaryFile()
        let original = Data("{\"schemaVersion\":1,\"selectedMode\":\"blank\",\"noteText\":\"keep\",\"blankTitle\":\"title\",\"blankBackground\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1},\"isPinned\":false}".utf8)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = WorkspaceFileStore(fileURL: file, now: { fixedDate })
        try original.write(to: file)
        let first = try XCTUnwrap(try store.load().migrationBackupURL)
        let firstModified = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date
        )

        let second = try XCTUnwrap(try store.load().migrationBackupURL)

        XCTAssertEqual(first, second)
        let backups = try FileManager.default.contentsOfDirectory(
            at: file.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("workspace-v1.backup-") }
        XCTAssertEqual(backups.count, 1)
        let secondModified = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(firstModified, secondModified)
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: second), original)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testSaveRejectsSchemaV1() throws {
        var content = WorkspaceContent.default
        content.schemaVersion = 1

        XCTAssertThrowsError(try WorkspaceFileStore(fileURL: try temporaryFile()).save(content))
    }

    func testNaNColorFailsSaveWithoutChangingFileOrClearingDirtyState() throws {
        try assertNonFiniteColorRejected(.nan, channel: \.red, name: "red")
    }

    func testInfinityColorFailsSaveWithoutChangingFileOrClearingDirtyState() throws {
        try assertNonFiniteColorRejected(.infinity, channel: \.alpha, name: "alpha")
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

    private func assertNonFiniteColorRejected(
        _ value: Double,
        channel: WritableKeyPath<RGBAColor, Double>,
        name: String
    ) throws {
        let file = try temporaryFile()
        let files = WorkspaceFileStore(fileURL: file)
        try files.save(.default)
        let original = try Data(contentsOf: file)
        let scheduler = ManualSaveScheduler()
        let store = try ContentStore(
            loader: files,
            scheduler: scheduler,
            saver: WorkspaceSaveWorker(store: files)
        )
        store.update { $0.blankBackground[keyPath: channel] = value }
        scheduler.fire()
        let failed = expectation(description: "\(name) save fails")
        store.flush { result in
            if case .success = result {
                XCTFail("Expected non-finite \(name) to fail")
            }
            failed.fulfill()
        }

        wait(for: [failed], timeout: 1)
        XCTAssertTrue(store.isDirty)
        XCTAssertFalse(store.content.blankBackground[keyPath: channel].isFinite)
        guard case .failed(let message) = store.saveState else {
            return XCTFail("Expected failed save state")
        }
        XCTAssertTrue(message.contains(name))
        XCTAssertTrue(message.contains("finite"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
