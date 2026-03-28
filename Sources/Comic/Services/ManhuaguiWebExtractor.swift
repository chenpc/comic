import Foundation
import WebKit

private let wkLogURL = URL(fileURLWithPath: "/tmp/comic_mhg.log")
private func mlog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: wkLogURL.path),
           let fh = try? FileHandle(forWritingTo: wkLogURL) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: wkLogURL)
        }
    }
}

/// 用 WKWebView 載入漫畫章節頁，攔截 SMH.imgData 取得圖片 URL
@MainActor
final class ManhuaguiWebExtractor: NSObject {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[URL], Error>?
    private var finished = false

    func fetchImageURLs(chapterURL: URL) async throws -> [URL] {
        mlog("  WKWebView fetchImageURLs start url=\(chapterURL)")
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.startLoading(chapterURL: chapterURL)
        }
    }

    private func startLoading(chapterURL: URL) {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // 攔截 SMH.imgData —— 兩種方式都試：
        // 1. 用 Object.defineProperty 監聽 SMH 被賦值
        // 2. 直接把資料存到 window._comic_imgData 供 didFinish 讀取
        let interceptScript = WKUserScript(source: """
            (function() {
                window._comic_imgData = null;
                var _smh = undefined;

                function sendData(data) {
                    try {
                        window._comic_imgData = data;
                        window.webkit.messageHandlers.imgData.postMessage(JSON.stringify(data));
                    } catch(e) {}
                }

                function interceptImgDataProp(obj) {
                    // 攔截 SMH.imgData 的屬性賦值（應對 SMH.imgData = function... 的情況）
                    var _fn = obj.imgData;
                    try {
                        Object.defineProperty(obj, 'imgData', {
                            configurable: true,
                            get: function() { return _fn; },
                            set: function(f) {
                                _fn = function(data) {
                                    sendData(data);
                                    return f.call(this, data);
                                };
                            }
                        });
                    } catch(e) {}
                    // 如果 imgData 已存在則直接 wrap
                    if (typeof _fn === 'function') {
                        var orig = _fn;
                        _fn = function(data) {
                            sendData(data);
                            return orig.call(this, data);
                        };
                    }
                }

                try {
                    Object.defineProperty(window, 'SMH', {
                        configurable: true,
                        get: function() { return _smh; },
                        set: function(v) {
                            _smh = v;
                            if (_smh && typeof _smh === 'object') {
                                interceptImgDataProp(_smh);
                            }
                        }
                    });
                } catch(e) {}
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(interceptScript)
        contentController.add(ScriptMessageHandlerWrapper(owner: self), name: "imgData")

        config.userContentController = contentController

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        var req = URLRequest(url: chapterURL)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        req.setValue("https://tw.manhuagui.com", forHTTPHeaderField: "Referer")
        mlog("  WKWebView loading \(chapterURL.absoluteString)")
        wv.load(req)

        // 60 秒逾時
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self, !self.finished else { return }
            mlog("  WKWebView timeout")
            self.finish(with: .failure(ExtractorError.timeout))
        }
    }

    fileprivate func handleMessage(_ body: String) {
        mlog("  WKWebView imgData message received len=\(body.count)")
        guard !finished else { return }
        // 若 JSON 有 server 欄位直接解析；若無，等 didFinish 再從 SMH.getImage 取伺服器
        if body.contains("\"server\"") {
            parseAndFinish(jsonStr: body, serverOverride: nil)
        } else {
            // 先存起來，等 didFinish 時加入 server 資訊
            pendingImgDataJSON = body
        }
    }

    private var pendingImgDataJSON: String? = nil

    // didFinish 後的 fallback：主動讀 window._comic_imgData
    private func queryFallback() {
        guard !finished, let wv = webView else { return }
        mlog("  WKWebView didFinish, evaluating fallback JS")

        // 嘗試從 SMH.getImage(0) 取得第一張圖的完整 URL，再推算 server
        let js = """
        (function() {
          try {
            // 方法1: SMH.getImage 直接回傳完整 URL
            if (typeof SMH !== 'undefined' && typeof SMH.getImage === 'function') {
              var url = SMH.getImage(0);
              if (url) return JSON.stringify({method:'getImage', url: url});
            }
            // 方法2: 從 DOM 找第一張已載入的圖片
            var imgs = document.images;
            for (var i = 0; i < imgs.length; i++) {
              var src = imgs[i].src || imgs[i].getAttribute('data-src') || '';
              if (src && (src.indexOf('hamreus') >= 0 || src.indexOf('.jpg') >= 0 || src.indexOf('.webp') >= 0)) {
                return JSON.stringify({method:'dom', url: src});
              }
            }
            // 方法3: 回傳 SMH 的原始 server 欄位（若有）
            if (typeof SM_CID !== 'undefined') return JSON.stringify({method:'SM_CID', val: JSON.stringify(SM_CID)});
          } catch(e) { return JSON.stringify({method:'error', err: e.toString()}); }
          return null;
        })()
        """
        wv.evaluateJavaScript(js) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, !self.finished else { return }
                mlog("  WKWebView server query result=\(String(describing: result))")

                var serverOverride: String? = nil
                if let str = result as? String,
                   let d = str.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    if let url = obj["url"] as? String {
                        // 從完整 URL 提取 server（scheme://host）
                        if let u = URL(string: url), let host = u.host {
                            serverOverride = "//" + host
                            mlog("  WKWebView inferred server=\(serverOverride!)")
                        }
                    }
                }

                if let pending = self.pendingImgDataJSON {
                    self.pendingImgDataJSON = nil
                    self.parseAndFinish(jsonStr: pending, serverOverride: serverOverride)
                } else if let json = (result as? String).flatMap({ _ in self.pendingImgDataJSON }) {
                    self.pendingImgDataJSON = nil
                    self.parseAndFinish(jsonStr: json, serverOverride: serverOverride)
                } else {
                    mlog("  WKWebView no pending imgData, err=\(String(describing: error))")
                    self.finish(with: .failure(ExtractorError.parseError))
                }
            }
        }
    }

    private func parseAndFinish(jsonStr: String, serverOverride: String?) {
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            mlog("  WKWebView JSON parse failed")
            finish(with: .failure(ExtractorError.parseError))
            return
        }
        guard let files = obj["files"] as? [String],
              let path  = obj["path"]  as? String else {
            mlog("  WKWebView missing files/path, keys=\(obj.keys.sorted())")
            finish(with: .failure(ExtractorError.parseError))
            return
        }
        let server = (obj["server"] as? String) ?? serverOverride ?? ""
        mlog("  WKWebView server='\(server)' path='\(path)' files=\(files.count)")

        let sl = obj["sl"] as? [String: Any]
        let e  = sl?["e"] as? Int
        let m  = sl?["m"] as? String

        // path 可能含中文需編碼；files 已是 percent-encoded，不可再編碼
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let urls: [URL] = files.compactMap { file -> URL? in
            // file 已是 percent-encoded（如 "01%20%E6%8B%B7%E8%B4%9D.jpg.webp"），直接使用
            var s = "https:" + server + encodedPath + file
            if let e = e, let m = m { s += "?e=\(e)&m=\(m)" }
            return URL(string: s)
        }
        mlog("  WKWebView parsed \(urls.count) image URLs, first=\(urls.first?.absoluteString ?? "-")")
        finish(with: .success(urls))
    }

    private func finish(with result: Result<[URL], Error>) {
        guard !finished else { return }
        finished = true
        let cont = continuation
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        cont?.resume(with: result)
    }

    enum ExtractorError: LocalizedError {
        case timeout, parseError, navigationFailed(String)
        var errorDescription: String? {
            switch self {
            case .timeout:                     return "頁面載入逾時"
            case .parseError:                  return "圖片資料解析失敗"
            case .navigationFailed(let s):     return "頁面載入失敗：\(s)"
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension ManhuaguiWebExtractor: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            mlog("  WKWebView didFinish")
            self?.queryFallback()
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            mlog("  WKWebView didFail: \(error.localizedDescription)")
            self?.finish(with: .failure(ExtractorError.navigationFailed(error.localizedDescription)))
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            mlog("  WKWebView didFailProvisional: \(error.localizedDescription)")
            self?.finish(with: .failure(ExtractorError.navigationFailed(error.localizedDescription)))
        }
    }
}

// MARK: - ScriptMessageHandler
private final class ScriptMessageHandlerWrapper: NSObject, WKScriptMessageHandler {
    weak var owner: ManhuaguiWebExtractor?
    init(owner: ManhuaguiWebExtractor) { self.owner = owner }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        Task { @MainActor [weak self] in
            self?.owner?.handleMessage(body)
        }
    }
}
