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

    func testImageAndWebAreNotEnabledInPhaseOne() {
        XCTAssertTrue(WorkspaceMode.note.isEnabledInPhase1)
        XCTAssertTrue(WorkspaceMode.blank.isEnabledInPhase1)
        XCTAssertFalse(WorkspaceMode.image.isEnabledInPhase1)
        XCTAssertFalse(WorkspaceMode.web.isEnabledInPhase1)
    }
}
