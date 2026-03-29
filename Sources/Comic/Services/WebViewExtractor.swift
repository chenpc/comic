import Foundation
import WebKit

/// 用 WKWebView 載入網頁（繞過 Cloudflare 驗證），執行 JS 取得頁面資料
@MainActor
final class WebViewExtractor: NSObject {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var pendingScript: String = ""
    private var extraDelay: Double = 1.5
    private var userAgent: String
    private var referer: String
    private var cookies: [HTTPCookie]
    /// 在 document 解析前注入的 JS（用於覆蓋 cookie 函數等）
    private var injectedScripts: [String]
    /// loadHTMLString 模式下，攔截並取消後續 location 跳轉
    nonisolated(unsafe) private var blockRedirects = false
    /// 第一次 decidePolicyFor 已放行，後續全部攔截
    nonisolated(unsafe) private var initialNavAllowed = false

    init(userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
         referer: String = "",
         cookies: [HTTPCookie] = [],
         injectedScripts: [String] = []) {
        self.userAgent = userAgent
        self.referer = referer
        self.cookies = cookies
        self.injectedScripts = injectedScripts
    }

    // MARK: - Public API

    /// 直接載入 HTML 字串（而非遠端 URL），讓 WebView 在 baseURL 環境下執行 script
    /// 適用於已用 URLSession 取得 HTML、不想讓 WebView 觸發重導的場景
    static func evaluateHTML(html: String, baseURL: URL, script: String, delay: Double = 1.5,
                             injectedScripts: [String] = []) async throws -> String {
        let extractor = WebViewExtractor(injectedScripts: injectedScripts)
        extractor.pendingScript = script
        extractor.extraDelay = delay
        extractor.blockRedirects = true
        return try await withCheckedThrowingContinuation { cont in
            extractor.continuation = cont
            extractor.startLoadingHTML(html: html, baseURL: baseURL)
        }
    }

    /// 載入 url，等頁面 didFinish + extraDelay 秒後執行 script，回傳 JSON 字串
    func evaluate(url: URL, script: String, delay: Double = 1.5) async throws -> String {
        pendingScript = script
        extraDelay = delay
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.startLoading(url: url)
        }
    }

    // MARK: - Private

    private func startLoading(url: URL) {
        let config = WKWebViewConfiguration()
        // 注入腳本（atDocumentStart，在頁面 JS 執行前）
        for src in injectedScripts {
            let script = WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                           configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !referer.isEmpty { req.setValue(referer, forHTTPHeaderField: "Referer") }

        if cookies.isEmpty {
            wv.load(req)
        } else {
            // 先注入 cookies，再載入頁面
            let cookieStore = config.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                cookieStore.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [weak wv] in
                wv?.load(req)
            }
        }

        // 全域逾時 60 秒
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, !self.finished else { return }
            self.finish(with: .failure(WVError.timeout))
        }
    }

    private func startLoadingHTML(html: String, baseURL: URL) {
        let config = WKWebViewConfiguration()
        for src in injectedScripts {
            let script = WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                           configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        wv.loadHTMLString(html, baseURL: baseURL)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, !self.finished else { return }
            self.finish(with: .failure(WVError.timeout))
        }
    }

    fileprivate func didFinishNavigation() {
        scheduleEvaluation()
    }

    /// 輪詢確認頁面已通過 CF 驗證，再執行 JS；最多等 30 秒
    private func scheduleEvaluation(attempt: Int = 0) {
        guard !finished, webView != nil else { return }
        let checkJS = "JSON.stringify({title: document.title, bodySnippet: document.body ? document.body.innerText.substring(0, 300) : ''})"
        Task { @MainActor [weak self] in
            guard let self, !self.finished, let wv = self.webView else { return }
            let raw = (try? await wv.evaluateJavaScript(checkJS) as? String) ?? ""
            let isCFChallenge: Bool
            if let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = obj["title"] as? String ?? ""
                let body  = obj["bodySnippet"] as? String ?? ""
                isCFChallenge = title.contains("人机验证") || title.contains("Just a moment")
                    || body.contains("人机验证") || body.contains("Just a moment")
            } else {
                isCFChallenge = raw.contains("人机验证") || raw.contains("Just a moment")
            }
            if isCFChallenge && attempt < 25 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.scheduleEvaluation(attempt: attempt + 1)
                return
            }
            // 頁面就緒，等額外延遲再執行 JS
            try? await Task.sleep(nanoseconds: UInt64(self.extraDelay * 1_000_000_000))
            guard !self.finished, let wv = self.webView else { return }
            do {
                let result = try await wv.evaluateJavaScript(self.pendingScript)
                if let str = result as? String {
                    self.finish(with: .success(str))
                } else {
                    self.finish(with: .failure(WVError.parseError))
                }
            } catch {
                self.finish(with: .failure(error))
            }
        }
    }

    fileprivate func finish(with result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        let cont = continuation
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        cont?.resume(with: result)
    }

    enum WVError: LocalizedError {
        case timeout, parseError, navFailed(String)
        var errorDescription: String? {
            switch self {
            case .timeout:          return "頁面載入逾時"
            case .parseError:       return "資料解析失敗"
            case .navFailed(let s): return "頁面載入失敗：\(s)"
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension WebViewExtractor: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // WKNavigationDelegate 在主執行緒呼叫，可直接存取 nonisolated(unsafe) 變數
        // blockRedirects 模式：只允許第一次載入，後續全部取消（防止 JS redirect）
        guard blockRedirects else {
            decisionHandler(.allow)
            return
        }
        if !initialNavAllowed {
            initialNavAllowed = true
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in self?.didFinishNavigation() }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish(with: .failure(WVError.navFailed(error.localizedDescription))) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish(with: .failure(WVError.navFailed(error.localizedDescription))) }
    }
}
