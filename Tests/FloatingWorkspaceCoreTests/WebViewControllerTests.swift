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

    func testRequestedHTTPNavigationFinishingBlankShowsNetworkFailure() throws {
        let controller = try makeController()
        let navigation = try XCTUnwrap(controller.load(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/unreachable"))
        ))
        _ = controller.webView.loadHTMLString("", baseURL: nil)
        controller.webView(controller.webView, didStartProvisionalNavigation: navigation)
        controller.webView(controller.webView, didFinish: navigation)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertTrue(controller.errorLabel.stringValue.hasPrefix("网络加载失败："))
    }

    func testOnlyLatestRequestedCancellationShowsNetworkFailure() throws {
        let controller = try makeController()
        let first = try XCTUnwrap(controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/first"))))
        let second = try XCTUnwrap(controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/second"))))
        let fallback = try loadHTML("<html><body><p>fallback</p></body></html>", in: controller)
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        controller.webView(controller.webView, didStartProvisionalNavigation: first)
        controller.webView(controller.webView, didStartProvisionalNavigation: second)
        controller.webView(controller.webView, didStartProvisionalNavigation: fallback)

        controller.webView(controller.webView, didFailProvisionalNavigation: first, withError: cancelled)
        XCTAssertEqual(controller.errorLabel.stringValue, "")
        XCTAssertEqual(controller.statusLabel.stringValue, "正在加载")

        controller.webView(controller.webView, didFailProvisionalNavigation: second, withError: cancelled)
        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertTrue(controller.errorLabel.stringValue.hasPrefix("网络加载失败："))
    }

    func testBlankCompletionAfterFailureKeepsErrorUntilNextSuccessfulNavigation() throws {
        let controller = try makeController()
        let navigation = try loadHTML("<html><body><p>keep me</p></body></html>", in: controller)
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."]
        )
        controller.webView(controller.webView, didStartProvisionalNavigation: navigation)
        controller.webView(controller.webView, didFailProvisionalNavigation: navigation, withError: error)
        XCTAssertEqual(controller.errorLabel.stringValue, "网络加载失败：Could not connect to the server.")

        controller.webView(controller.webView, didStartProvisionalNavigation: navigation)
        controller.webView(controller.webView, didFinish: navigation)

        XCTAssertEqual(controller.statusLabel.stringValue, "加载失败")
        XCTAssertEqual(controller.errorLabel.stringValue, "网络加载失败：Could not connect to the server.")

        let next = try loadHTML("<html><body><p>next</p></body></html>", in: controller)
        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/next")))
        controller.webView(controller.webView, didStartProvisionalNavigation: next)
        controller.webView(controller.webView, didFinish: next)
        XCTAssertEqual(controller.statusLabel.stringValue, "加载完成")
        XCTAssertEqual(controller.errorLabel.stringValue, "")
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

    func testFlushDraftSanitizesActiveContentAndFormState() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "HTTPS://Example.COM:443/sanitize#section"))
        _ = try loadHTML(
            """
            <html><body>
            <p id='ordinary' onclick='window.__clicked = true'>ordinary text</p>
            <script>window.__scriptRan = true</script>
            <a id='unsafe-link' href='javascript:window.__linkRan = true'>link</a>
            <iframe src='about:blank'></iframe><object></object><embed>
            <frame src='about:blank'><portal src='about:blank'></portal><applet></applet>
            <base href='https://example.com/base'>
            <meta http-equiv='refresh' content='0;url=http://127.0.0.1:9/elsewhere'>
            <svg><a href='https://example.com/safe'><set attributeName='href' to='javascript:window.__svgSet = true'></set><animate attributeName='href' values='https://example.com/safe;javascript:window.__svgAnimate = true'></animate></a></svg>
            <template id='active-template'><script>window.__templateScript = true</script><frameset><frame src='about:blank'></frameset><svg><set attributeName='href' by='javascript:window.__nestedSvg = true'></set></svg></template>
            <form id='form' action='https://example.com/submit' method='post'>
            <input id='password' type='password' value='s3cr3t'>
            <textarea id='note'>private note</textarea>
            <button formmethod='post' formtarget='_blank'>submit</button>
            </form>
            </body></html>
            """,
            baseURL: url,
            in: controller
        )
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('ordinary').textContent = 'ordinary text'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let flushed = expectation(description: "sanitized draft flushed")

        controller.flushDraft {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 2)

        let draft = try XCTUnwrap(try drafts.draft(for: url))
        let html = draft.sanitizedBodyHTML
        let lowercaseHTML = html.lowercased()
        XCTAssertEqual(draft.url, "https://example.com/sanitize")
        XCTAssertTrue(html.contains("ordinary text"))
        XCTAssertTrue(html.contains("id='ordinary'") || html.contains("id=\"ordinary\""))
        XCTAssertFalse(lowercaseHTML.contains("<script"))
        XCTAssertFalse(lowercaseHTML.contains("<iframe"))
        XCTAssertFalse(lowercaseHTML.contains("<object"))
        XCTAssertFalse(lowercaseHTML.contains("<embed"))
        XCTAssertFalse(lowercaseHTML.contains("<frame"))
        XCTAssertFalse(lowercaseHTML.contains("<portal"))
        XCTAssertFalse(lowercaseHTML.contains("<applet"))
        XCTAssertFalse(lowercaseHTML.contains("<base"))
        XCTAssertFalse(lowercaseHTML.contains("<set"))
        XCTAssertFalse(lowercaseHTML.contains("<animate"))
        XCTAssertFalse(lowercaseHTML.contains("http-equiv=\"refresh\""))
        XCTAssertFalse(lowercaseHTML.contains("http-equiv='refresh'"))
        XCTAssertFalse(lowercaseHTML.contains("onclick"))
        XCTAssertFalse(lowercaseHTML.contains("javascript:"))
        XCTAssertFalse(html.contains("s3cr3t"))
        XCTAssertFalse(html.contains("private note"))
        XCTAssertFalse(lowercaseHTML.contains("action="))
        XCTAssertFalse(lowercaseHTML.contains("method="))
        XCTAssertFalse(lowercaseHTML.contains("formmethod"))
        XCTAssertFalse(lowercaseHTML.contains("formtarget"))
    }

    func testMutationSavesOnlyAfterEightHundredMillisecondsIdle() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/idle"))
        _ = try loadHTML("<html><body><p id='text'>original</p></body></html>", baseURL: url, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'edited after pause'", in: controller)
        XCTAssertNil(try drafts.draft(for: url))
        let earlyCheckpoint = expectation(description: "300ms checkpoint")
        let saveCheckpoint = expectation(description: "idle save checkpoint")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertNil(try? drafts.draft(for: url))
            earlyCheckpoint.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            saveCheckpoint.fulfill()
        }

        wait(for: [earlyCheckpoint, saveCheckpoint], timeout: 2)

        let draft = try XCTUnwrap(try drafts.draft(for: url))
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("edited after pause"))
    }

    func testDidFinishReplaysSanitizedDraftOnce() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let url = try XCTUnwrap(URL(string: "https://example.com/replay"))
        let saved = WebDraft(
            url: url.absoluteString,
            sanitizedBodyHTML: """
                <p id='restored'>restored draft</p>
                <script>window.__replayScript = true</script>
                <svg><a href='https://example.com/safe'><set attributeName='href' to='javascript:window.__svgReplay = true'></set><animate attributeName='href' values='javascript:window.__svgReplay = true'></animate></a></svg>
                <frame src='about:blank'><frameset></frameset><portal></portal><applet></applet><base href='https://example.com/base'>
                <template id='draft-template'><script>window.__templateReplay = true</script><svg><animate attributeName='href' from='javascript:window.__nestedReplay = true'></animate></svg><form><button formmethod='post' formtarget='_blank'>submit</button></form></template>
                """,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try drafts.saveDraft(saved)
        let controller = try makeController(store: drafts)
        let finished = expectation(description: "page loaded")
        let navigationDelegate = NavigationForwardingDelegate(forwarded: controller) {
            finished.fulfill()
        }
        controller.webView.navigationDelegate = navigationDelegate
        let navigation = controller.webView.loadHTMLString(
            "<html><body><p>remote page</p></body></html>",
            baseURL: url
        )
        wait(for: [finished], timeout: 5)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "已恢复上次修改"),
            object: controller.statusLabel
        )
        wait(for: [restored], timeout: 2)

        XCTAssertEqual(
            try evaluate("document.getElementById('restored').textContent", in: controller) as? String,
            "restored draft"
        )
        XCTAssertEqual(try evaluate("document.querySelector('script') === null", in: controller) as? Bool, true)
        XCTAssertEqual(try evaluate("window.__replayScript === undefined", in: controller) as? Bool, true)
        let replayedHTML = try XCTUnwrap(try evaluate("document.body.innerHTML", in: controller) as? String)
        XCTAssertFalse(replayedHTML.lowercased().contains("javascript:"))
        XCTAssertEqual(
            try evaluate("document.body.querySelectorAll('frame, frameset, portal, applet, base, set, animate').length", in: controller) as? Int,
            0
        )
        XCTAssertEqual(
            try evaluate("document.getElementById('draft-template').content.querySelectorAll('script, frame, frameset, portal, applet, base, set, animate, [formmethod], [formtarget]').length", in: controller) as? Int,
            0
        )
        XCTAssertEqual(
            try evaluate("document.getElementById('draft-template').content.querySelector('svg').innerHTML.includes('javascript:')", in: controller) as? Bool,
            false
        )

        _ = try evaluate("document.body.innerHTML = '<p>subsequent page change</p>'", in: controller)
        controller.webView(controller.webView, didFinish: navigation)
        let replayWindow = expectation(description: "replay window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            replayWindow.fulfill()
        }
        wait(for: [replayWindow], timeout: 1)

        XCTAssertEqual(try evaluate("document.body.textContent", in: controller) as? String, "subsequent page change")
        XCTAssertEqual(try drafts.draft(for: url), saved)
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testReplayFailureReportsErrorAndPreservesDraft() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let url = try XCTUnwrap(URL(string: "https://example.com/replay-error"))
        let saved = WebDraft(
            url: url.absoluteString,
            sanitizedBodyHTML: "<p>keep this draft</p>",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try drafts.saveDraft(saved)
        let controller = try makeController(store: drafts)
        let navigation = try loadHTML("<html><body><p>remote page</p></body></html>", baseURL: url, in: controller)
        _ = try evaluate("document.body.remove()", in: controller)

        controller.webView(controller.webView, didFinish: navigation)
        let failed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "无法应用上次修改"),
            object: controller.errorLabel
        )
        wait(for: [failed], timeout: 2)

        XCTAssertEqual(try drafts.draft(for: url), saved)
        XCTAssertNotEqual(controller.statusLabel.stringValue, "已恢复上次修改")
    }

    func testNavigationFlushesCurrentDraftBeforeProvisionalNavigation() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/current"))
        _ = try loadHTML("<html><body><p id='text'>original</p></body></html>", baseURL: currentURL, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'saved before navigation'", in: controller)
        let started = expectation(description: "next navigation started")
        var draftAtNavigationStart: WebDraft?
        let navigationDelegate = NavigationForwardingDelegate(
            forwarded: controller,
            didStart: {
                draftAtNavigationStart = try? drafts.draft(for: currentURL)
                started.fulfill()
            },
            didFinish: {}
        )
        controller.webView.navigationDelegate = navigationDelegate

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/next")))
        wait(for: [started], timeout: 5)

        let draft = try XCTUnwrap(draftAtNavigationStart)
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("saved before navigation"))
        controller.webView.stopLoading()
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testEditingWithoutMutationDoesNotSaveOnEndEditOrNavigation() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/untouched"))
        _ = try loadHTML("<html><body><p>live content</p></body></html>", baseURL: currentURL, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "false")
        let started = expectation(description: "next navigation started")
        var draftAtNavigationStart: WebDraft?
        let navigationDelegate = NavigationForwardingDelegate(
            forwarded: controller,
            didStart: {
                draftAtNavigationStart = try? drafts.draft(for: currentURL)
                started.fulfill()
            },
            didFinish: {}
        )
        controller.webView.navigationDelegate = navigationDelegate

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/untouched-next")))
        wait(for: [started], timeout: 5)

        XCTAssertNil(draftAtNavigationStart)
        XCTAssertTrue(doubles.store.content.webDrafts.isEmpty)
        XCTAssertNotEqual(controller.statusLabel.stringValue, "已恢复上次修改")
        controller.webView.stopLoading()
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testNavigationFlushesNewMutationMadeWithinEightHundredMillisecondsAfterIdleSave() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/latest-navigation-edit"))
        _ = try loadHTML("<html><body><p id='text'>original</p></body></html>", baseURL: currentURL, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'first autosave'", in: controller)
        _ = try waitForDraft(containing: "first autosave", for: currentURL, in: drafts)
        _ = try evaluate("document.getElementById('text').textContent = 'latest navigation edit'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let started = expectation(description: "next navigation started")
        var draftAtNavigationStart: WebDraft?
        let navigationDelegate = NavigationForwardingDelegate(
            forwarded: controller,
            didStart: {
                draftAtNavigationStart = try? drafts.draft(for: currentURL)
                started.fulfill()
            },
            didFinish: {}
        )
        controller.webView.navigationDelegate = navigationDelegate

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/latest-navigation-next")))
        wait(for: [started], timeout: 5)

        let draft = try XCTUnwrap(draftAtNavigationStart)
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("latest navigation edit"))
        XCTAssertFalse(draft.sanitizedBodyHTML.contains("first autosave"))
        controller.webView.stopLoading()
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testPageWorldCannotInvokeDraftMessageHandler() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/isolated-handler"))
        _ = try loadHTML("<html><body><p>unchanged</p></body></html>", baseURL: url, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")

        let invoked = try evaluate(
            """
            (() => {
                const handler = window.webkit?.messageHandlers?.floatingWorkspaceDraftIdle;
                if (!handler) { return false; }
                handler.postMessage({ kind: 'dirty' });
                return true;
            })()
            """,
            in: controller
        ) as? Bool

        XCTAssertEqual(invoked, false)
        let flushed = expectation(description: "clean flush completed")
        controller.flushDraft { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)
        XCTAssertNil(try drafts.draft(for: url))
    }

    func testPageCloneOverrideCannotTamperWithSanitizedSave() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/isolated-save"))
        _ = try loadHTML("<html><body><p id='text'>safe original</p></body></html>", baseURL: url, in: controller)
        _ = try evaluate(
            """
            Element.prototype.cloneNode = function() {
                const clone = document.createElement('body');
                clone.innerHTML = '<p id="tampered">tampered save</p>';
                return clone;
            };
            true;
            """,
            in: controller
        )
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'safe edited text'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let flushed = expectation(description: "sanitized draft flushed")

        controller.flushDraft { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let draft = try XCTUnwrap(try drafts.draft(for: url))
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("safe edited text"))
        XCTAssertFalse(draft.sanitizedBodyHTML.contains("tampered save"))
    }

    func testPageDOMImplementationOverrideCannotTamperWithReplay() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let url = try XCTUnwrap(URL(string: "https://example.com/isolated-replay"))
        let saved = WebDraft(
            url: url.absoluteString,
            sanitizedBodyHTML: "<p id='restored'>safe replay</p>",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try drafts.saveDraft(saved)
        let controller = try makeController(store: drafts)
        let navigation = try loadHTML("<html><body><p>remote page</p></body></html>", baseURL: url, in: controller)
        _ = try evaluate(
            "DOMImplementation.prototype.createHTMLDocument = function() { throw new Error('page override'); }; true;",
            in: controller
        )

        controller.webView(controller.webView, didFinish: navigation)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "已恢复上次修改"),
            object: controller.statusLabel
        )
        wait(for: [restored], timeout: 2)

        XCTAssertEqual(try evaluate("document.getElementById('restored').textContent", in: controller) as? String, "safe replay")
        XCTAssertEqual(controller.errorLabel.stringValue, "")
    }

    func testReplayJavaScriptThrowReportsErrorAndPreservesDraft() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let url = try XCTUnwrap(URL(string: "https://example.com/replay-throws"))
        let saved = WebDraft(
            url: url.absoluteString,
            sanitizedBodyHTML: "<p>keep thrown replay draft</p>",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try drafts.saveDraft(saved)
        let controller = try makeController(store: drafts)
        let navigation = try loadHTML("<html><body><p>remote page</p></body></html>", baseURL: url, in: controller)
        _ = try evaluateInDraftWorld(
            "DOMImplementation.prototype.createHTMLDocument = function() { throw new Error('injected replay failure'); }; true;",
            in: controller
        )

        controller.webView(controller.webView, didFinish: navigation)
        let failed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "无法应用上次修改"),
            object: controller.errorLabel
        )
        wait(for: [failed], timeout: 2)

        XCTAssertEqual(try drafts.draft(for: url), saved)
        XCTAssertNotEqual(controller.statusLabel.stringValue, "已恢复上次修改")
    }

    func testNavigationDraftJavaScriptThrowCancelsNavigationAndRetainsDirtyState() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/navigation-save-throws"))
        _ = try loadHTML("<html><body><p id='text'>dirty edit</p></body></html>", baseURL: currentURL, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'must remain dirty'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        _ = try evaluateInDraftWorld(
            "Element.prototype.cloneNode = function() { throw new Error('injected navigation save failure'); }; true;",
            in: controller
        )
        var navigationStartCount = 0
        let navigationDelegate = NavigationForwardingDelegate(
            forwarded: controller,
            didStart: { navigationStartCount += 1 },
            didFinish: {}
        )
        controller.webView.navigationDelegate = navigationDelegate

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/must-not-start")))
        let outcomeDeadline = Date().addingTimeInterval(2)
        while navigationStartCount == 0,
              !controller.errorLabel.stringValue.contains("无法保存网页草稿"),
              Date() < outcomeDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(navigationStartCount, 0)
        XCTAssertTrue(controller.needsDraftFlush)
        XCTAssertTrue(controller.errorLabel.stringValue.contains("无法保存网页草稿"))
        XCTAssertNil(try drafts.draft(for: currentURL))
        controller.webView.stopLoading()
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testNoscriptMarkupCannotBreakOutIntoActiveContentOnSaveOrReplay() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/noscript-breakout"))
        _ = try loadHTML("<html><body><p id='editable-text'>plain body</p></body></html>", baseURL: url, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        // Build the noscript subtree through the live DOM so the raw-text body parser is
        // not what protects us, then add the crafted inert title text.
        _ = try evaluate(
            """
            (() => {
                const noscript = document.createElement('noscript');
                const paragraph = document.createElement('p');
                paragraph.setAttribute('title', '</noscript><img src=x onerror="window.__noscriptSaveRan = true">');
                noscript.appendChild(paragraph);
                document.body.insertBefore(noscript, document.getElementById('editable-text'));
                document.getElementById('editable-text').textContent = 'noscript saved';
                return true;
            })()
            """,
            in: controller
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let flushed = expectation(description: "sanitized draft flushed")

        controller.flushDraft { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let draft = try XCTUnwrap(try drafts.draft(for: url))
        let savedHTML = draft.sanitizedBodyHTML.lowercased()
        XCTAssertFalse(savedHTML.contains("<noscript"))
        XCTAssertFalse(savedHTML.contains("<noembed"))
        XCTAssertFalse(savedHTML.contains("<noframes"))
        XCTAssertFalse(savedHTML.contains("onerror"))
        XCTAssertTrue(savedHTML.contains("noscript saved"))

        let seededHTML = """
            <noscript><p title="</noscript><img src=x onerror="window.__noscriptReplayRan = true">"></p></noscript>
            <noembed>&lt;img src=x onerror=window.__noembedRan=true&gt;</noembed>
            <noframes>&lt;img src=x onerror=window.__noframesRan=true&gt;</noframes>
            <p id='seeded'>seeded replay body</p>
            """
        try drafts.saveDraft(WebDraft(
            url: url.absoluteString,
            sanitizedBodyHTML: seededHTML,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let replayController = try makeController(store: drafts)
        let finished = expectation(description: "replay target loaded")
        let navigationDelegate = NavigationForwardingDelegate(forwarded: replayController) {
            finished.fulfill()
        }
        replayController.webView.navigationDelegate = navigationDelegate
        _ = replayController.webView.loadHTMLString(
            "<html><body><p>remote page</p></body></html>",
            baseURL: url
        )
        wait(for: [finished], timeout: 5)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "已恢复上次修改"),
            object: replayController.statusLabel
        )
        wait(for: [restored], timeout: 2)

        XCTAssertEqual(
            try evaluate("document.body.innerHTML.includes('seeded replay body')", in: replayController) as? Bool,
            true
        )
        XCTAssertEqual(
            try evaluate("document.body.querySelectorAll('noscript, noembed, noframes, img').length", in: replayController) as? Int,
            0
        )
        XCTAssertEqual(
            try evaluate(
                "window.__noscriptSaveRan === undefined && window.__noscriptReplayRan === undefined && window.__noembedRan === undefined && window.__noframesRan === undefined",
                in: replayController
            ) as? Bool,
            true
        )
        replayController.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testSavedDraftStripsPingAttributeButKeepsOrdinaryLinkNavigation() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/ping"))
        _ = try loadHTML(
            """
            <html><body>
            <p id='editable-text'>ping fixture</p>
            <a id='ping-link' href='https://example.com/target' ping='https://127.0.0.1:9/track'>ordinary link</a>
            </body></html>
            """,
            baseURL: url,
            in: controller
        )
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('editable-text').textContent = 'ping edited'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let flushed = expectation(description: "sanitized draft flushed")

        controller.flushDraft { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let draft = try XCTUnwrap(try drafts.draft(for: url))
        XCTAssertFalse(draft.sanitizedBodyHTML.lowercased().contains("ping="))
        XCTAssertFalse(draft.sanitizedBodyHTML.contains("127.0.0.1:9"))
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("https://example.com/target"))
        XCTAssertTrue(draft.sanitizedBodyHTML.contains("ping edited"))
    }

    func testWebContentProcessTerminationClearsPendingEditsAndShowsLossNotice() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/terminated"))
        _ = try loadHTML("<html><body><p id='text'>original</p></body></html>", baseURL: url, in: controller)
        controller.toggleEditing()
        XCTAssertTrue(controller.isEditing)
        _ = try evaluate("document.getElementById('text').textContent = 'lost edit'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.needsDraftFlush)

        controller.webViewWebContentProcessDidTerminate(controller.webView)

        XCTAssertFalse(controller.isEditing)
        XCTAssertFalse(controller.needsDraftFlush)
        XCTAssertEqual(controller.errorLabel.stringValue, "网页进程已终止，未保存的网页修改已丢失")
        XCTAssertEqual(controller.editButton.title, "编辑正文")

        let navigation = try loadHTML("<html><body><p id='fresh'>fresh page</p></body></html>", baseURL: url, in: controller)
        controller.webView(controller.webView, didFinish: navigation)

        XCTAssertNil(try drafts.draft(for: url))
        XCTAssertEqual(controller.errorLabel.stringValue, "")
    }

    func testFailedFlushAllowsNextUserNavigationOnceWithVisibleWarning() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let currentURL = try XCTUnwrap(URL(string: "https://example.com/failed-flush"))
        _ = try loadHTML("<html><body><p id='text'>original</p></body></html>", baseURL: currentURL, in: controller)
        controller.toggleEditing()
        XCTAssertEqual(try evaluate("document.body.contentEditable", in: controller) as? String, "true")
        _ = try evaluate("document.getElementById('text').textContent = 'cannot be saved'", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        _ = try evaluateInDraftWorld(
            "Element.prototype.cloneNode = function() { throw new Error('injected flush failure'); }; true;",
            in: controller
        )
        var navigationStartCount = 0
        let navigationDelegate = NavigationForwardingDelegate(
            forwarded: controller,
            didStart: { navigationStartCount += 1 },
            didFinish: {}
        )
        controller.webView.navigationDelegate = navigationDelegate

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/first-attempt")))
        let firstDeadline = Date().addingTimeInterval(2)
        while navigationStartCount == 0,
              !controller.errorLabel.stringValue.contains("无法保存网页草稿"),
              Date() < firstDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(navigationStartCount, 0)
        XCTAssertTrue(controller.needsDraftFlush)

        controller.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:9/second-attempt")))
        let secondDeadline = Date().addingTimeInterval(2)
        while navigationStartCount == 0 && Date() < secondDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(navigationStartCount, 1)
        XCTAssertTrue(controller.errorLabel.stringValue.contains("未保存的网页修改"))
        XCTAssertFalse(controller.isEditing)
        controller.webView.stopLoading()
        controller.webView.navigationDelegate = nil
        withExtendedLifetime(navigationDelegate) {}
    }

    func testSubframeSrcDocIsAllowedWithoutMainFrameErrorOrDraftWrite() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/subframe"))
        _ = try loadHTML("<html><body><iframe id='frame'></iframe></body></html>", baseURL: url, in: controller)
        controller.toggleEditing()
        XCTAssertTrue(controller.isEditing)
        _ = try evaluate("document.getElementById('frame').srcdoc = '<p>subframe content</p>'; true", in: controller)
        let deadline = Date().addingTimeInterval(1)
        var frameText: String?
        while Date() < deadline, frameText?.contains("subframe content") != true {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            _ = try? evaluate("true", in: controller)
            frameText = try? evaluate(
                "document.getElementById('frame').contentDocument?.body?.textContent ?? ''",
                in: controller
            ) as? String
        }

        XCTAssertEqual(frameText?.contains("subframe content"), true)
        XCTAssertEqual(controller.errorLabel.stringValue, "")
        XCTAssertTrue(controller.isEditing)
        XCTAssertTrue(try drafts.draft(for: url) == nil)
    }

    func testSubframeActionPolicyIsolatedFromMainFrameFlushFailureAndErrorLabel() throws {
        let doubles = try ContentStoreTestDoubles()
        let drafts = WebDraftStore(store: doubles.store)
        let controller = try makeController(store: drafts)
        let url = try XCTUnwrap(URL(string: "https://example.com/subframe-policy"))
        XCTAssertTrue(controller.webView.navigationDelegate === controller)
        controller.webView.loadHTMLString(
            "<html><body><iframe id='frame'></iframe></body></html>",
            baseURL: url
        )
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "stringValue == %@", "加载完成"),
            object: controller.statusLabel
        )
        wait(for: [loaded], timeout: 5)
        controller.toggleEditing()
        XCTAssertTrue(controller.isEditing)
        _ = try evaluate("document.body.insertAdjacentText('beforeend', ' dirty subframe action')", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(controller.needsDraftFlush)
        _ = try evaluateInDraftWorld(
            "Element.prototype.cloneNode = function() { throw new Error('injected subframe flush failure'); }; true;",
            in: controller
        )

        _ = try evaluate("document.getElementById('frame').srcdoc = '<p>subframe survives</p>'; true", in: controller)
        let deadline = Date().addingTimeInterval(1)
        var frameText: String?
        while Date() < deadline, frameText?.contains("subframe survives") != true {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            frameText = try? evaluate(
                "document.getElementById('frame').contentDocument?.body?.textContent ?? ''",
                in: controller
            ) as? String
        }

        XCTAssertEqual(frameText?.contains("subframe survives"), true)
        XCTAssertEqual(controller.errorLabel.stringValue, "")
        XCTAssertNil(try drafts.draft(for: url))
        XCTAssertTrue(controller.needsDraftFlush)
    }

    func testFlushDraftWithoutPendingChangesCompletesImmediately() throws {
        let controller = try makeController()
        var completionCount = 0

        controller.flushDraft {
            completionCount += 1
        }

        XCTAssertEqual(completionCount, 1)
    }

    private func waitForDraft(
        containing text: String,
        for url: URL,
        in drafts: WebDraftStore,
        timeout: TimeInterval = 2
    ) throws -> WebDraft {
        let deadline = Date().addingTimeInterval(timeout)
        var matched: WebDraft?
        while matched == nil && Date() < deadline {
            if let draft = try drafts.draft(for: url), draft.sanitizedBodyHTML.contains(text) {
                matched = draft
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        return try XCTUnwrap(matched)
    }

    private func evaluateInDraftWorld(_ script: String, in controller: WebViewController) throws -> Any? {
        let completed = expectation(description: "isolated JavaScript evaluation completed")
        var result: Any?
        var evaluationError: Error?
        controller.webView.evaluateJavaScript(
            script,
            in: nil,
            in: .world(name: "FloatingWorkspace.WebDraft")
        ) { completion in
            switch completion {
            case .success(let value):
                result = value
            case .failure(let error):
                evaluationError = error
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        if let evaluationError {
            throw evaluationError
        }
        return result
    }

    private func makeStore() throws -> WebDraftStore {
        WebDraftStore(store: try ContentStoreTestDoubles().store)
    }

    private func makeController(store: WebDraftStore? = nil) throws -> WebViewController {
        let controller = WebViewController(store: try store ?? makeStore())
        _ = controller.view
        return controller
    }

    private func loadHTML(_ html: String, baseURL: URL? = nil, in controller: WebViewController) throws -> WKNavigation {
        let finished = expectation(description: "local HTML navigation finished")
        let navigationDelegate = LocalNavigationDelegate {
            finished.fulfill()
        }
        controller.webView.navigationDelegate = navigationDelegate
        let navigation = controller.webView.loadHTMLString(html, baseURL: baseURL)
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
    private let didStart: (() -> Void)?
    private let didFinish: () -> Void

    init(
        forwarded: WebViewController,
        didStart: (() -> Void)? = nil,
        didFinish: @escaping () -> Void
    ) {
        self.forwarded = forwarded
        self.didStart = didStart
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        forwarded?.webView(webView, didStartProvisionalNavigation: navigation)
        didStart?()
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
