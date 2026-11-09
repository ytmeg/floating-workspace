import AppKit
import Foundation
import WebKit

@MainActor
public final class WebViewController: NSViewController {
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

    public init(store: WebDraftStore) {
        self.store = store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
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

    public func load(url: URL) {
        if let message = validationError(for: url) {
            showError(message)
            return
        }

        errorLabel.stringValue = ""
        urlField.stringValue = url.absoluteString
        statusLabel.stringValue = "正在加载"
        webView.load(URLRequest(url: url))
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

        webView.evaluateJavaScript(editingScript(enabled: requestedState)) { [weak self] result, error in
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
        }
    }

    public func flushDraft(completion: @escaping () -> Void) {
        completion()
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

        let toolbar = NSStackView(views: [
            backButton,
            forwardButton,
            refreshButton,
            urlField,
            openButton,
            editButton
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8)
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

    private func editingScript(enabled: Bool) -> String {
        """
        (() => {
            const body = document.body;
            if (!body) {
                return { ok: false, reason: 'no-body' };
            }
            const handlerKey = '__floatingWorkspaceWebModeSubmitInterceptor';
            if (\(enabled)) {
                body.contentEditable = 'true';
                if (!window[handlerKey]) {
                    window[handlerKey] = event => {
                        event.preventDefault();
                        event.stopImmediatePropagation();
                    };
                    document.addEventListener('submit', window[handlerKey], true);
                }
            } else {
                body.contentEditable = 'false';
                if (window[handlerKey]) {
                    document.removeEventListener('submit', window[handlerKey], true);
                    delete window[handlerKey];
                }
            }
            return { ok: true, contentEditable: body.contentEditable };
        })()
        """
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
        statusLabel.stringValue = "正在加载"
        errorLabel.stringValue = ""
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url {
            urlField.stringValue = url.absoluteString
        }
        updateNavigationButtons()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.stringValue = "加载完成"
        errorLabel.stringValue = ""
        if let url = webView.url {
            urlField.stringValue = url.absoluteString
        }
        updateNavigationButtons()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            showError("请输入有效的 http 或 https 链接")
            decisionHandler(.cancel)
            return
        }
        if let message = navigationValidationError(for: url) {
            showError(message)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
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

    private func handleNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

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
