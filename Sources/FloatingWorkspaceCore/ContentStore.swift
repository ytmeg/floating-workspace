import Combine
import Foundation

@MainActor
public final class ContentStore: ObservableObject {
    @Published public private(set) var content: WorkspaceContent
    @Published public private(set) var saveState: SaveState = .saved
    public private(set) var isDirty = false
    public private(set) var isSaving = false
    public let recoveryURL: URL?

    private let scheduler: any SaveScheduling
    private let saver: any WorkspaceSaving
    private var revision = 0
    private var flushCompletions: [(Result<Void, Error>) -> Void] = []

    public convenience init(fileURL: URL) throws {
        let files = WorkspaceFileStore(fileURL: fileURL)
        try self.init(
            loader: files,
            scheduler: TimerSaveScheduler(),
            saver: WorkspaceSaveWorker(store: files)
        )
    }

    public init(
        loader: any WorkspacePersisting,
        scheduler: any SaveScheduling,
        saver: any WorkspaceSaving
    ) throws {
        let result = try loader.load()
        content = result.content
        recoveryURL = result.recoveryURL
        self.scheduler = scheduler
        self.saver = saver
    }

    public func update(_ mutation: (inout WorkspaceContent) -> Void) {
        revision += 1
        mutation(&content)
        isDirty = true
        saveState = .saving
        scheduler.schedule(after: 0.3) { [weak self] in
            self?.flush()
        }
    }

    public func flush(completion: ((Result<Void, Error>) -> Void)? = nil) {
        scheduler.cancel()
        if let completion {
            flushCompletions.append(completion)
        }
        guard !isSaving else { return }
        guard isDirty else {
            completeFlushCompletions(with: .success(()))
            return
        }

        let saveRevision = revision
        let snapshot = content
        isSaving = true
        saveState = .saving
        saver.save(snapshot) { [weak self] result in
            Task { @MainActor in
                self?.finishSave(result, savedRevision: saveRevision)
            }
        }
    }

    private func finishSave(_ result: Result<Void, Error>, savedRevision: Int) {
        isSaving = false
        switch result {
        case .success:
            guard savedRevision == revision else {
                flush()
                return
            }
            isDirty = false
            saveState = .saved
            completeFlushCompletions(with: .success(()))
        case .failure(let error):
            saveState = .failed(error.localizedDescription)
            completeFlushCompletions(with: .failure(error))
        }
    }

    private func completeFlushCompletions(with result: Result<Void, Error>) {
        let completions = flushCompletions
        flushCompletions.removeAll()
        completions.forEach { $0(result) }
    }
}
