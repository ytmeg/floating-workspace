import Foundation
@testable import FloatingWorkspaceCore

struct FakeWorkspaceLoader: WorkspacePersisting {
    var content: WorkspaceContent = .default
    var recoveryURL: URL?

    func load() throws -> WorkspaceLoadResult {
        WorkspaceLoadResult(content: content, recoveryURL: recoveryURL)
    }

    func save(_ content: WorkspaceContent) throws {}
}

@MainActor
final class ManualSaveScheduler: SaveScheduling {
    private(set) var delays: [TimeInterval] = []
    private var action: (() -> Void)?

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        delays.append(delay)
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let action = self.action
        self.action = nil
        action?()
    }
}

final class ControlledWorkspaceSaver: WorkspaceSaving {
    private(set) var snapshots: [WorkspaceContent] = []
    private var completions: [(Result<Void, Error>) -> Void] = []

    func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void) {
        snapshots.append(content)
        completions.append(completion)
    }

    func completeSuccess(at index: Int) {
        completions[index](.success(()))
    }

    func completeFailure(at index: Int) {
        completions[index](.failure(NSError(
            domain: "ContentStoreTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test save failure"]
        )))
    }
}

@MainActor
struct ContentStoreTestDoubles {
    let scheduler: ManualSaveScheduler
    let saver: ControlledWorkspaceSaver
    let store: ContentStore

    init() throws {
        let loader = FakeWorkspaceLoader()
        scheduler = ManualSaveScheduler()
        saver = ControlledWorkspaceSaver()
        store = try ContentStore(loader: loader, scheduler: scheduler, saver: saver)
    }
}
