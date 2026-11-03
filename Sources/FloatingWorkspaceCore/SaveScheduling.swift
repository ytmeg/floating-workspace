import Foundation

@MainActor
public protocol SaveScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

@MainActor
public final class TimerSaveScheduler: SaveScheduling {
    private var timer: Timer?
    public init() {}
    public func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        // Common modes keep autosave running during menu tracking, scrolling and live resize.
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

public protocol WorkspaceSaving {
    func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void)
}

public final class WorkspaceSaveWorker: WorkspaceSaving {
    private let store: WorkspaceFileStore
    private let queue = DispatchQueue(label: "local.floatingworkspace.save", qos: .utility)

    public init(store: WorkspaceFileStore) { self.store = store }

    public func save(_ content: WorkspaceContent, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            completion(Result { try self.store.save(content) })
        }
    }
}
