import AppKit
import WebKit
import XCTest
@testable import FloatingWorkspaceCore

@MainActor
final class WebViewControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testBrowserUsesNonPersistentDataStoreAndOwnsToolbar() throws {
        let controller = try makeController()

        XCTAssertFalse(controller.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(controller.openButton.title, "打开")
        XCTAssertEqual(controller.backButton.title, "后退")
        XCTAssertEqual(controller.forwardButton.title, "前进")
        XCTAssertEqual(controller.refreshButton.title, "刷新")
        XCTAssertEqual(controller.editButton.title, "编辑正文")
        XCTAssertTrue(controller.urlField.superview != nil)
        XCTAssertTrue(controller.webView.superview != nil)
        XCTAssertTrue(controller.statusLabel.superview != nil)
        XCTAssertTrue(controller.errorLabel.superview != nil)
    }

    func testEditingToggleUsesLocalContentEditable() throws {
        let controller = try makeController()
        _ = try loadHTML("<html><body><p>hello</p></body></html>", in: controller)

        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        XCTAssertTrue(controller.isEditing)
        XCTAssertEqual(controller.editButton.title, "结束编辑")

        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "false")
        XCTAssertFalse(controller.isEditing)
        XCTAssertEqual(controller.editButton.title, "编辑正文")
    }

    func testSubmitIsInterceptedOnlyWhileEditing() throws {
        let controller = try makeController()
        _ = try loadHTML("<html><body><form id='form'></form></body></html>", in: controller)
        let dispatchSubmit = """
            document.getElementById('form').dispatchEvent(
                new Event('submit', { bubbles: true, cancelable: true })
            )
            """

        controller.toggleEditing()
        XCTAssertEqual(try evaluate(dispatchSubmit, in: controller) as? Bool, false)

        controller.toggleEditing()
        XCTAssertEqual(try evaluate(dispatchSubmit, in: controller) as? Bool, true)
    }

    func testInvalidURLDoesNotCreateRequest() throws {
        let controller = try makeController()
        controller.urlField.stringValue = "file:///tmp/private.html"

        controller.openURLFromField()

        XCTAssertNil(controller.webView.url)
        XCTAssertEqual(controller.errorLabel.stringValue, "仅支持 http 和 https 链接")
    }

    func testCredentialURLDoesNotCreateRequestOrExposePassword() throws {
        let controller = try makeController()
        let password = "s3cr3t"
        controller.urlField.stringValue = "https://user:\(password)@example.com/private"

        controller.openURLFromField()

        XCTAssertNil(controller.webView.url)
        XCTAssertEqual(controller.errorLabel.stringValue, "链接不能包含用户名或密码")
        XCTAssertFalse(controller.errorLabel.stringValue.contains(password))
    }

    func testMalformedURLDoesNotCreateRequest() throws {
        let controller = try makeController()
        controller.urlField.stringValue = "not a URL"

        controller.openURLFromField()

        XCTAssertNil(controller.webView.url)
        XCTAssertEqual(controller.errorLabel.stringValue, "请输入有效的 http 或 https 链接")
    }

    func testMalformedAuthorityFieldEntriesDoNotCreateRequestsOrMutateInput() throws {
        let invalidInputs = [
            "https:///private",
            "https://example.com:abc/private",
            "https://example.com:99999/private",
            "https://example.com:443:8443/private"
        ]

        for raw in invalidInputs {
            let controller = try makeController()
            controller.urlField.stringValue = raw

            controller.openURLFromField()

            XCTAssertNil(controller.webView.url, raw)
            XCTAssertEqual(controller.urlField.stringValue, raw, raw)
            XCTAssertEqual(controller.errorLabel.stringValue, "请输入有效的 http 或 https 链接", raw)
        }
    }

    func testDirectLoadRejectsMalformedAuthoritiesWithoutMutatingURL() throws {
        let invalidInputs = [
            "https:///private",
            "https://example.com:99999/private"
        ]

        for raw in invalidInputs {
            let url = try XCTUnwrap(URL(string: raw), raw)
            let controller = try makeController()

            controller.load(url: url)

            XCTAssertNil(controller.webView.url, raw)
            XCTAssertEqual(url.absoluteString, raw, raw)
            XCTAssertEqual(controller.urlField.stringValue, "", raw)
            XCTAssertEqual(controller.errorLabel.stringValue, "请输入有效的 http 或 https 链接", raw)
        }
    }

    func testAuthenticationChallengeUsesDefaultHandlingWithoutCredential() throws {
        let controller = try makeController()
        let sender = FakeAuthenticationChallengeSender()
        let protectionSpace = URLProtectionSpace(
            host: "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 1,
            failureResponse: nil,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted),
            sender: sender
        )
        var disposition: URLSession.AuthChallengeDisposition?
        var credential: URLCredential?

        controller.webView(controller.webView, didReceive: challenge) { completedDisposition, completedCredential in
            disposition = completedDisposition
            credential = completedCredential
        }

        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertNil(credential)
        withExtendedLifetime(sender) {}
    }

    func testNoBodyShowsVisibleErrorAndDoesNotEnterEditing() throws {
        let controller = try makeController()
        _ = try loadHTML("<html><body><p>remove me</p></body></html>", in: controller)
        _ = try evaluate("document.body.remove()", in: controller)
        XCTAssertEqual(try evaluate("document.body === null", in: controller) as? Bool, true)

        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body === null", in: controller) as? Bool, true)

        XCTAssertEqual(controller.errorLabel.stringValue, "无法编辑：页面没有正文")
        XCTAssertFalse(controller.isEditing)
        XCTAssertEqual(controller.editButton.title, "编辑正文")
    }

    func testNavigationCompletionUpdatesStatusAndCurrentURL() throws {
        let controller = try makeController()
        XCTAssertTrue(controller.webView.navigationDelegate === controller)
        let navigation = try loadHTML("<html><body><p>hello</p></body></html>", in: controller)

        controller.webView(controller.webView, didStartProvisionalNavigation: navigation)
        XCTAssertEqual(controller.statusLabel.stringValue, "正在加载")
        controller.webView(controller.webView, didFinish: navigation)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载完成")
        XCTAssertEqual(controller.urlField.stringValue, controller.webView.url?.absoluteString)
        XCTAssertEqual(controller.errorLabel.stringValue, "")
    }

    func testNetworkFailureShowsErrorAndPreservesCurrentBody() throws {
        let controller = try makeController()
        let navigation = try loadHTML("<html><body><p>keep me</p></body></html>", in: controller)
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "测试网络断开"]
        )

        controller.webView(controller.webView, didFailProvisionalNavigation: navigation, withError: error)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertEqual(controller.errorLabel.stringValue, "网络加载失败：测试网络断开")
        XCTAssertEqual(try evaluate("document.body.textContent", in: controller) as? String, "keep me")
    }

    func testCertificateFailureShowsReadableErrorAndPreservesCurrentBody() throws {
        let controller = try makeController()
        let navigation = try loadHTML("<html><body><p>keep me</p></body></html>", in: controller)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)

        controller.webView(controller.webView, didFailProvisionalNavigation: navigation, withError: error)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertEqual(controller.errorLabel.stringValue, "证书验证失败，已停止加载")
        XCTAssertEqual(try evaluate("document.body.textContent", in: controller) as? String, "keep me")
    }

    func testCommittedNavigationFailureAlsoShowsVisibleError() throws {
        let controller = try makeController()
        let navigation = try loadHTML("<html><body><p>keep me</p></body></html>", in: controller)
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: "连接中断"]
        )

        controller.webView(controller.webView, didFail: navigation, withError: error)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertEqual(controller.errorLabel.stringValue, "网络加载失败：连接中断")
    }

    func testNewWindowLinkLoadsBlankDocumentInSameWebView() throws {
        let controller = try makeController()
        XCTAssertTrue(controller.webView.uiDelegate === controller)
        let firstFinish = expectation(description: "source document finished")
        let secondFinish = expectation(description: "new-window target finished in same web view")
        var finishCount = 0
        let navigationDelegate = NavigationForwardingDelegate(forwarded: controller) {
            finishCount += 1
            if finishCount == 1 {
                firstFinish.fulfill()
            } else {
                secondFinish.fulfill()
            }
        }
        controller.webView.navigationDelegate = navigationDelegate
        controller.webView.loadHTMLString(
            "<html><body><a id='new-window' target='_blank' href='about:blank'>open</a></body></html>",
            baseURL: nil
        )
        wait(for: [firstFinish], timeout: 5)

        _ = try evaluate("document.getElementById('new-window').click()", in: controller)
        wait(for: [secondFinish], timeout: 5)

        XCTAssertEqual(controller.webView.url?.absoluteString, "about:blank")
        XCTAssertEqual(
            try evaluate("document.getElementById('new-window') === null", in: controller) as? Bool,
            true
        )
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testFlushDraftStubCompletesImmediately() throws {
        let controller = try makeController()
        var completionCount = 0

        controller.flushDraft {
            completionCount += 1
        }

        XCTAssertEqual(completionCount, 1)
    }

    private func makeStore() throws -> WebDraftStore {
        WebDraftStore(store: try ContentStoreTestDoubles().store)
    }

    private func makeController() throws -> WebViewController {
        let controller = WebViewController(store: try makeStore())
        _ = controller.view
        return controller
    }

    private func loadHTML(_ html: String, in controller: WebViewController) throws -> WKNavigation {
        let finished = expectation(description: "local HTML navigation finished")
        let navigationDelegate = LocalNavigationDelegate {
            finished.fulfill()
        }
        controller.webView.navigationDelegate = navigationDelegate
        let navigation = controller.webView.loadHTMLString(html, baseURL: nil)
        wait(for: [finished], timeout: 5)
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
        return try XCTUnwrap(navigation)
    }

    private func evaluate(_ script: String, in controller: WebViewController) throws -> Any? {
        let completed = expectation(description: "JavaScript evaluation completed")
        var result: Any?
        var evaluationError: Error?
        controller.webView.evaluateJavaScript(script) { value, error in
            result = value
            evaluationError = error
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        if let evaluationError {
            throw evaluationError
        }
        return result
    }
}

private final class FakeAuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

@MainActor
private final class NavigationForwardingDelegate: NSObject, WKNavigationDelegate {
    private weak var forwarded: WebViewController?
    private let didFinish: () -> Void

    init(forwarded: WebViewController, didFinish: @escaping () -> Void) {
        self.forwarded = forwarded
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        forwarded?.webView(webView, didFinish: navigation)
        didFinish()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        forwarded?.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
}

@MainActor
private final class LocalNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}
