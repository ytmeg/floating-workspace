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
        do {
            let content = try JSONDecoder().decode(WorkspaceContent.self, from: data)
            return WorkspaceLoadResult(content: content, recoveryURL: nil)
        } catch {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")
            let directory = fileURL.deletingLastPathComponent()
            var backup = directory.appendingPathComponent("workspace-v1.corrupt-\(stamp).json")
            var counter = 2
            while FileManager.default.fileExists(atPath: backup.path) {
                backup = directory.appendingPathComponent("workspace-v1.corrupt-\(stamp)-\(counter).json")
                counter += 1
            }
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return WorkspaceLoadResult(content: .default, recoveryURL: backup)
        }
    }

    public func save(_ content: WorkspaceContent) throws {
        guard content.schemaVersion == 1 else {
            throw NSError(
                domain: "WorkspaceFileStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported workspace schema version: \(content.schemaVersion)"]
            )
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
