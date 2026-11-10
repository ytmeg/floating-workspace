import AppKit
import Foundation
import WebKit

@MainActor
public final class WebViewController: NSViewController {
    private static let draftContentWorld = WKContentWorld.world(name: "FloatingWorkspace.WebDraft")
    public let store: WebDraftStore
    public let webView: WKWebView
    public let urlField = NSTextField()
    public let openButton = NSButton()
    public let backButton = NSButton()
    public let forwardButton = NSButton()
    public let refreshButton = NSButton()
    public let editButton = NSButton()
    public let statusLabel = NSTextField(labelWithString: "")
    public let errorLabel = NSTextField(labelWithString: "")
    public private(set) var isEditing = false
    public var needsDraftFlush: Bool {
        hasPendingDraftChanges || isFlushingDraft
    }
    private var hasPendingDraftChanges = false
    private var isFlushingDraft = false
    private var draftFlushCompletions: [(Result<Void, Error>) -> Void] = []
    private var replayAttempted = false
    private var navigationGeneration = 0
    private var navigationFailureGeneration: Int?
    private var latestRequestedNavigation: WKNavigation?
    private var latestRequestedURL: URL?
    private var currentDocumentURL: URL?
    private var allowMainFrameNavigationAfterFlushFailure = false
    private var pendingDraftLossWarning: String?

    static let processTerminationMessage = "网页进程已终止，未保存的网页修改已丢失"
    static let navigationDraftLossWarning = "无法保存网页草稿，继续导航会丢失未保存的网页修改"

    public init(store: WebDraftStore) {
        self.store = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        configuration.userContentController.add(
            WeakWebDraftMessageHandler(delegate: self),
            contentWorld: Self.draftContentWorld,
            name: WebDraftSanitizer.messageHandlerName
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        updateNavigationButtons()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 540))
        configureToolbar()
        configureLabels()
        layoutContent()
    }

    @discardableResult
    public func load(url: URL) -> WKNavigation? {
        if let message = validationError(for: url) {
            showError(message)
            return nil
        }

        errorLabel.stringValue = ""
        urlField.stringValue = url.absoluteString
        statusLabel.stringValue = "正在加载"
        navigationFailureGeneration = nil
        if currentDocumentURL == nil {
            currentDocumentURL = webView.url
        }
        let navigation = webView.load(URLRequest(url: url))
        latestRequestedNavigation = navigation
        latestRequestedURL = url
        return navigation
    }

    @objc public func openURLFromField() {
        let input = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input) else {
            showError("请输入有效的 http 或 https 链接")
            return
        }
        load(url: url)
    }

    @objc public func toggleEditing() {
        let requestedState = !isEditing
        isEditing = requestedState
        updateEditButton()
        errorLabel.stringValue = ""

        evaluateDraftJavaScript(WebDraftSanitizer.setEditing(enabled: requestedState)) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.isEditing = !requestedState
                self.updateEditButton()
                self.showError("无法切换编辑状态：\(error.localizedDescription)")
                return
            }
            guard let result = result as? [String: Any],
                  let succeeded = result["ok"] as? Bool else {
                self.isEditing = !requestedState
                self.updateEditButton()
                self.showError("无法切换编辑状态")
                return
            }
            guard succeeded else {
                self.isEditing = false
                self.updateEditButton()
                self.showError("无法编辑：页面没有正文")
                return
            }
            self.errorLabel.stringValue = ""
            if !requestedState && self.hasPendingDraftChanges {
                self.flushDraft { (_: Result<Void, Error>) in }
            }
        }
    }

    public func flushDraft(completion: @escaping () -> Void) {
        flushDraft { (_: Result<Void, Error>) in
            completion()
        }
    }

    public func flushDraft(completion: @escaping (Result<Void, Error>) -> Void) {
        flushDraft(sourceURL: currentDocumentURL ?? webView.url, completion: completion)
    }

    private func flushDraft(sourceURL: URL?, completion: @escaping (Result<Void, Error>) -> Void) {
        draftFlushCompletions.append(completion)
        guard !isFlushingDraft else { return }
        guard hasPendingDraftChanges else {
            completeDraftFlush(with: .success(()))
            return
        }
        guard let url = sourceURL,
              let normalizedURL = try? WebDraftKey.normalized(url) else {
            completeDraftFlush(with: .success(()))
            return
        }

        isFlushingDraft = true
        evaluateDraftJavaScript(WebDraftSanitizer.sanitizeBody()) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.completeDraftFlush(with: .failure(error))
                return
            }
            guard let result = result as? [String: Any],
                  let succeeded = result["ok"] as? Bool,
                  succeeded,
                  let html = result["html"] as? String else {
                self.completeDraftFlush(with: .failure(Self.draftError("页面没有可保存的正文")))
                return
            }

            do {
                try self.store.saveDraft(WebDraft(
                    url: normalizedURL,
                    sanitizedBodyHTML: html,
                    updatedAt: Date()
                ))
                self.completeDraftFlush(with: .success(()))
            } catch {
                self.completeDraftFlush(with: .failure(error))
            }
        }
    }

    private func completeDraftFlush(with result: Result<Void, Error>) {
        isFlushingDraft = false
        switch result {
        case .success:
            hasPendingDraftChanges = false
            pendingDraftLossWarning = nil
        case .failure(let error):
            allowMainFrameNavigationAfterFlushFailure = true
            showError("无法保存网页草稿：\(error.localizedDescription)")
        }
        let completions = draftFlushCompletions
        draftFlushCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func discardPendingDraftChangesShowingLossWarning() {
        hasPendingDraftChanges = false
        isEditing = false
        updateEditButton()
        pendingDraftLossWarning = Self.navigationDraftLossWarning
        showError(Self.navigationDraftLossWarning)
    }

    private func evaluateDraftJavaScript(
        _ script: String,
        completion: @escaping (Any?, Error?) -> Void
    ) {
        webView.evaluateJavaScript(script, in: nil, in: Self.draftContentWorld) { result in
            switch result {
            case .success(let value):
                completion(value, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    private static func draftError(_ message: String) -> NSError {
        NSError(
            domain: "WebViewController",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func configureToolbar() {
        configure(button: backButton, title: "后退", identifier: "web-back", action: #selector(goBack))
        configure(button: forwardButton, title: "前进", identifier: "web-forward", action: #selector(goForward))
        configure(button: refreshButton, title: "刷新", identifier: "web-refresh", action: #selector(refresh))
        configure(button: openButton, title: "打开", identifier: "web-open", action: #selector(openURLFromField))
        configure(button: editButton, title: "编辑正文", identifier: "web-edit", action: #selector(toggleEditing))

        urlField.font = NSFont.systemFont(ofSize: 14)
        urlField.placeholderString = "https://example.com"
        urlField.target = self
        urlField.action = #selector(openURLFromField)
        urlField.setAccessibilityIdentifier("web-url")

        let navigationToolbar = NSStackView(views: [
            backButton,
            forwardButton,
            refreshButton,
            editButton
        ])
        navigationToolbar.orientation = .horizontal
        navigationToolbar.alignment = .centerY
        navigationToolbar.distribution = .equalSpacing
        navigationToolbar.spacing = 8
        navigationToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationToolbar)

        let addressToolbar = NSStackView(views: [urlField, openButton])
        addressToolbar.orientation = .horizontal
        addressToolbar.alignment = .centerY
        addressToolbar.spacing = 8
        addressToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addressToolbar)

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            navigationToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            navigationToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            navigationToolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            navigationToolbar.heightAnchor.constraint(equalToConstant: 32),
            addressToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            addressToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            addressToolbar.topAnchor.constraint(equalTo: navigationToolbar.bottomAnchor, constant: 8),
            addressToolbar.heightAnchor.constraint(equalToConstant: 32),
            urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: addressToolbar.bottomAnchor, constant: 8)
        ])
    }

    private func configureLabels() {
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("web-status")

        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 0
        errorLabel.setAccessibilityIdentifier("web-error")
    }

    private func layoutContent() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -4),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            errorLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            webView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8)
        ])
    }

    private func configure(button: NSButton, title: String, identifier: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private func updateEditButton() {
        editButton.title = isEditing ? "结束编辑" : "编辑正文"
    }

    private func validationError(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            return "请输入有效的 http 或 https 链接"
        }
        guard scheme == "http" || scheme == "https" else {
            return "仅支持 http 和 https 链接"
        }
        guard components.user == nil, components.password == nil else {
            return "链接不能包含用户名或密码"
        }
        do {
            _ = try WebDraftKey.normalized(url)
            return nil
        } catch {
            return "请输入有效的 http 或 https 链接"
        }
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func refresh() {
        webView.reload()
    }
}

extension WebViewController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            showError("请输入有效的 http 或 https 链接")
            return nil
        }
        if let message = navigationValidationError(for: url) {
            showError(message)
            return nil
        }

        errorLabel.stringValue = ""
        statusLabel.stringValue = "正在加载"
        webView.load(navigationAction.request)
        return nil
    }
}

extension WebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if navigationFailureGeneration != nil, webView.url?.absoluteString == "about:blank" {
            return
        }
        navigationGeneration += 1
        if latestRequestedNavigation == nil {
            latestRequestedNavigation = navigation
            latestRequestedURL = nil
        }
        replayAttempted = false
        isEditing = false
        hasPendingDraftChanges = false
        updateEditButton()
        statusLabel.stringValue = "正在加载"
        errorLabel.stringValue = pendingDraftLossWarning ?? ""
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentDocumentURL = webView.url
        if let url = webView.url {
            urlField.stringValue = url.absoluteString
        }
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.absoluteString == "about:blank",
           latestRequestedNavigation === navigation,
           let requestedURL = latestRequestedURL {
            latestRequestedNavigation = nil
            latestRequestedURL = nil
            statusLabel.stringValue = "加载失败"
            showError(pendingDraftLossWarning ?? "网络加载失败：无法加载 \(requestedURL.absoluteString)")
            updateNavigationButtons()
            return
        }
        // A failed load can produce later about:blank starts/finishes in new generations.
        // Suppress those fallback completions until an actual destination succeeds.
        if navigationFailureGeneration != nil {
            let completedURL = webView.url?.absoluteString
            guard completedURL != nil, completedURL != "about:blank" else { return }
            navigationFailureGeneration = nil
        }
        latestRequestedNavigation = nil
        latestRequestedURL = nil
        currentDocumentURL = webView.url
        statusLabel.stringValue = "加载完成"
        errorLabel.stringValue = pendingDraftLossWarning ?? ""
        if let url = webView.url {
            urlField.stringValue = url.absoluteString
        }
        updateNavigationButtons()
        replayDraftIfNeeded()
    }

    private func replayDraftIfNeeded() {
        guard !replayAttempted else { return }
        replayAttempted = true
        guard let url = webView.url,
              let draft = try? store.draft(for: url) else {
            return
        }
        let generation = navigationGeneration
        evaluateDraftJavaScript(WebDraftSanitizer.applySanitizedBody(draft.sanitizedBodyHTML)) { [weak self] result, error in
            guard let self, generation == self.navigationGeneration else { return }
            if error != nil {
                self.showError("无法应用上次修改")
                return
            }
            guard let result = result as? [String: Any],
                  let succeeded = result["ok"] as? Bool,
                  succeeded else {
                self.showError("无法应用上次修改")
                return
            }
            self.statusLabel.stringValue = "已恢复上次修改"
            self.errorLabel.stringValue = ""
        }
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error, navigation: navigation)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, navigation: navigation)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The web content process is gone: pending edits cannot be saved and any in-flight
        // JavaScript will never call back, so drop the state and say so plainly.
        hasPendingDraftChanges = false
        isEditing = false
        isFlushingDraft = false
        allowMainFrameNavigationAfterFlushFailure = false
        pendingDraftLossWarning = nil
        let completions = draftFlushCompletions
        draftFlushCompletions.removeAll()
        let error = Self.draftError(Self.processTerminationMessage)
        completions.forEach { $0(.failure(error)) }
        updateEditButton()
        statusLabel.stringValue = "加载失败"
        showError(Self.processTerminationMessage)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard let url = navigationAction.request.url else {
            if isMainFrame {
                showError("请输入有效的 http 或 https 链接")
            }
            decisionHandler(.cancel)
            return
        }
        guard isMainFrame else {
            // Subframe loads (including about:srcdoc) never carry the main document draft,
            // so they are validated on their own and never touch the main-frame error label.
            decisionHandler(subframePolicy(for: url))
            return
        }
        if let message = navigationValidationError(for: url) {
            showError(message)
            decisionHandler(.cancel)
            return
        }
        if allowMainFrameNavigationAfterFlushFailure {
            allowMainFrameNavigationAfterFlushFailure = false
            discardPendingDraftChangesShowingLossWarning()
            navigationFailureGeneration = nil
            decisionHandler(.allow)
            return
        }
        flushDraft(sourceURL: currentDocumentURL ?? webView.url) { result in
            switch result {
            case .success:
                self.navigationFailureGeneration = nil
                decisionHandler(.allow)
            case .failure:
                decisionHandler(.cancel)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // WebKit retains responsibility for evaluating server trust; no certificate bypass or credential persistence.
        completionHandler(.performDefaultHandling, nil)
    }

    private func navigationValidationError(for url: URL) -> String? {
        if url.absoluteString == "about:blank" {
            return nil
        }
        return validationError(for: url)
    }

    /// Subframes are allowed when they are inert local documents or ordinary web schemes.
    /// They are never allowed to inherit the main-frame URL contract (no http/https scheme
    /// requirement for `about:` documents) and never written into the main-frame error label.
    private func subframePolicy(for url: URL) -> WKNavigationActionPolicy {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme.isEmpty || scheme == "about" {
            return .allow
        }
        return validationError(for: url) == nil ? .allow : .cancel
    }

    private func handleNavigationFailure(_ error: Error, navigation: WKNavigation?) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled,
           navigation !== latestRequestedNavigation {
            return
        }

        navigationFailureGeneration = navigationGeneration
        latestRequestedURL = nil
        statusLabel.stringValue = "加载失败"
        switch nsError.code {
        case NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateUntrusted:
            showError("证书验证失败，已停止加载")
        default:
            showError("网络加载失败：\(error.localizedDescription)")
        }
        updateNavigationButtons()
    }
}

extension WebViewController: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == WebDraftSanitizer.messageHandlerName,
              isEditing,
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        switch kind {
        case "dirty":
            hasPendingDraftChanges = true
        case "idle":
            guard hasPendingDraftChanges else { return }
            flushDraft { (_: Result<Void, Error>) in }
        default:
            break
        }
    }
}

@MainActor
private final class WeakWebDraftMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
