import Foundation

public protocol WorkspacePersisting {
    func load() throws -> WorkspaceLoadResult
    func save(_ content: WorkspaceContent) throws
}

public struct WorkspaceFileStore: WorkspacePersisting {
    public let fileURL: URL
    private let now: () -> Date

    public init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    public func load() throws -> WorkspaceLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return WorkspaceLoadResult(content: .default, recoveryURL: nil)
        }

        let data = try Data(contentsOf: fileURL)
        let content: WorkspaceContent
        do {
            content = try JSONDecoder().decode(WorkspaceContent.self, from: data)
        } catch {
            return try recoverOriginal()
        }

        switch content.schemaVersion {
        case 1:
            var migrated = content
            migrated.schemaVersion = 2
            let backup = try writeMigrationBackup(data)
            return WorkspaceLoadResult(
                content: migrated,
                recoveryURL: nil,
                migrationBackupURL: backup
            )
        case 2:
            return WorkspaceLoadResult(content: content, recoveryURL: nil)
        default:
            return try recoverOriginal()
        }
    }

    private func existingMigrationBackup(matching data: Data) throws -> URL? {
        let directory = fileURL.deletingLastPathComponent()
        let candidates = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("workspace-v1.backup-") && $0.hasSuffix(".json") }
            .sorted()
            .map { directory.appendingPathComponent($0) }
        for candidate in candidates where try Data(contentsOf: candidate) == data {
            return candidate
        }
        return nil
    }

    private func writeMigrationBackup(_ data: Data) throws -> URL {
        if let existing = try existingMigrationBackup(matching: data) {
            return existing
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")
        let directory = fileURL.deletingLastPathComponent()
        var counter = 1
        while true {
            let suffix = counter == 1 ? "" : "-\(counter)"
            let backup = directory.appendingPathComponent("workspace-v1.backup-\(stamp)\(suffix).json")
            let staged = directory.appendingPathComponent(".\(UUID().uuidString)-workspace-v1.backup.tmp")
            defer { try? FileManager.default.removeItem(at: staged) }
            do {
                // This SDK traps on [.atomic, .withoutOverwriting]; staging plus a hard link preserves both guarantees.
                try data.write(to: staged, options: .atomic)
                try FileManager.default.linkItem(at: staged, to: backup)
                return backup
            } catch let error as NSError {
                guard error.domain == NSCocoaErrorDomain, error.code == NSFileWriteFileExistsError else {
                    throw error
                }
                if try Data(contentsOf: backup) == data {
                    return backup
                }
                counter += 1
            }
        }
    }

    private func recoverOriginal() throws -> WorkspaceLoadResult {
        let backup = unusedBackupURL(prefix: "workspace-v1.corrupt-")
        try FileManager.default.moveItem(at: fileURL, to: backup)
        return WorkspaceLoadResult(content: .default, recoveryURL: backup)
    }

    private func unusedBackupURL(prefix: String) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")
        let directory = fileURL.deletingLastPathComponent()
        var backup = directory.appendingPathComponent("\(prefix)\(stamp).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = directory.appendingPathComponent("\(prefix)\(stamp)-\(counter).json")
            counter += 1
        }
        return backup
    }

    public func save(_ content: WorkspaceContent) throws {
        guard content.schemaVersion == 2 else {
            throw NSError(
                domain: "WorkspaceFileStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported workspace schema version: \(content.schemaVersion)"]
            )
        }

        for (name, value) in [
            ("red", content.blankBackground.red),
            ("green", content.blankBackground.green),
            ("blue", content.blankBackground.blue),
            ("alpha", content.blankBackground.alpha)
        ] {
            guard value.isFinite else {
                throw NSError(
                    domain: "WorkspaceFileStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Blank background \(name) channel must be finite"]
                )
            }
        }

        var normalized = content
        normalized.blankBackground.red = min(max(normalized.blankBackground.red, 0), 1)
        normalized.blankBackground.green = min(max(normalized.blankBackground.green, 0), 1)
        normalized.blankBackground.blue = min(max(normalized.blankBackground.blue, 0), 1)
        normalized.blankBackground.alpha = min(max(normalized.blankBackground.alpha, 0), 1)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: fileURL, options: .atomic)
    }
}
