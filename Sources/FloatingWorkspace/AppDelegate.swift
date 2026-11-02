import AppKit
import FloatingWorkspaceCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: ContentStore?
    var windowController: FloatingWindowController?
    var workspaceViewController: WorkspaceViewController?
    var menuBarController: MenuBarController?
    var hotkeyController: HotkeyController?
    var terminationReplyHandler: (Bool) -> Void = {
        NSApp.reply(toApplicationShouldTerminate: $0)
    }
    var alertPresenter: (NSAlert) -> NSApplication.ModalResponse = {
        NSApp.activate(ignoringOtherApps: true)
        return $0.runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileURL = Self.workspaceFileURL()
        do {
            let fileStore = WorkspaceFileStore(fileURL: fileURL)
            let store = try ContentStore(
                loader: fileStore,
                scheduler: TimerSaveScheduler(),
                saver: WorkspaceSaveWorker(store: fileStore)
            )
            self.store = store

            let windowController = FloatingWindowController(store: store)
            self.windowController = windowController
            workspaceViewController = windowController.panel.contentViewController as? WorkspaceViewController
            menuBarController = MenuBarController(windowController: windowController)
            let hotkeyController = HotkeyController {
                windowController.togglePinned()
            }
            self.hotkeyController = hotkeyController
            windowController.show()

            if let recoveryURL = store.recoveryURL {
                presentRecovery(recoveryURL)
            }
            do {
                try hotkeyController.start()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "全局快捷键不可用"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "好")
                _ = alertPresenter(alert)
            }
        } catch {
            presentLoadFailure(error)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard !store.isDirty && !store.isSaving else {
            flushForTermination(using: store)
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }

    static func workspaceFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupport: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    ) -> URL {
        if let override = environment["FLOATING_WORKSPACE_STORE_URL"], !override.isEmpty {
            if let url = URL(string: override), url.isFileURL {
                return url
            }
            return URL(fileURLWithPath: override)
        }
        return applicationSupport
            .appendingPathComponent("FloatingWorkspace", isDirectory: true)
            .appendingPathComponent("workspace-v1.json")
    }

    @MainActor
    private func flushForTermination(using store: ContentStore) {
        store.flush { result in
            switch result {
            case .success:
                self.terminationReplyHandler(true)
            case .failure:
                self.presentTerminationSaveFailure()
            }
        }
    }

    @MainActor
    private func presentTerminationSaveFailure() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "退出前保存失败"
        alert.informativeText = "未保存的内容仍保留。你可以重试，或明确放弃未保存内容并退出。"
        alert.addButton(withTitle: "重试")
        alert.addButton(withTitle: "放弃未保存内容并退出")

        switch alertPresenter(alert) {
        case .alertFirstButtonReturn:
            if let store {
                flushForTermination(using: store)
            }
        case .alertSecondButtonReturn:
            terminationReplyHandler(true)
        default:
            terminationReplyHandler(false)
        }
    }

    @MainActor
    private func presentRecovery(_ recoveryURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "已恢复损坏的工作区文件"
        alert.informativeText = "原文件已保留为：\n\(recoveryURL.path)\n\n当前使用默认内容。"
        alert.addButton(withTitle: "好")
        _ = alertPresenter(alert)
    }

    @MainActor
    private func presentLoadFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "无法载入悬浮工作台"
        alert.informativeText = "\(error.localizedDescription)\n\n未修改原数据，应用将退出。"
        alert.addButton(withTitle: "退出悬浮工作台")
        _ = alertPresenter(alert)
        NSApplication.shared.terminate(nil)
    }
}
