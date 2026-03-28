import Foundation
import JavaScriptCore
import WebKit

private let mhgLogURL = URL(fileURLWithPath: "/tmp/comic_mhg.log")
private func mlog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: mhgLogURL.path),
           let fh = try? FileHandle(forWritingTo: mhgLogURL) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: mhgLogURL)
        }
    }
}

final class ManhuaguiService {
    static let shared = ManhuaguiService()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 60
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Referer":    "https://tw.manhuagui.com"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - 列表

    /// 取得漫畫列表（頁碼 1-based）
    /// filterSlugs: 依序組合的 slug，如 ["japan", "rexue"]，空陣列代表全部
    func fetchComicList(page: Int, search: String, filterSlugs: [String] = []) async throws -> (galleries: [Gallery], totalPages: Int) {
        let url: URL
        if !search.isEmpty {
            // 搜尋模式
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? search
            var comps = URLComponents(string: "https://tw.manhuagui.com/s/\(encoded)/")!
            if page > 1 { comps.queryItems = [URLQueryItem(name: "page", value: "\(page)")] }
            url = comps.url!
        } else if filterSlugs.isEmpty {
            // 無篩選
            let path = page <= 1 ? "/list/view.html" : "/list/view_p\(page).html"
            url = URL(string: "https://tw.manhuagui.com\(path)")!
        } else {
            // 有篩選：/list/{slug1}/{slug2}/  分頁：最後一個 slug 加 _p{N}
            if page <= 1 {
                let path = "/list/" + filterSlugs.joined(separator: "/") + "/"
                url = URL(string: "https://tw.manhuagui.com\(path)")!
            } else {
                let prefix = filterSlugs.dropLast().joined(separator: "/")
                let last   = filterSlugs.last!
                let path   = prefix.isEmpty
                    ? "/list/\(last)_p\(page).html"
                    : "/list/\(prefix)/\(last)_p\(page).html"
                url = URL(string: "https://tw.manhuagui.com\(path)")!
            }
        }
        mlog("fetchComicList page=\(page) search='\(search)' url=\(url)")
        let html: String
        do {
            html = try await fetchHTML(url: url)
        } catch {
            mlog("  fetchHTML error: \(error)")
            throw error
        }
        mlog("  html length=\(html.count)")
        mlog("  html prefix=\(String(html.prefix(300)).replacingOccurrences(of: "\n", with: "↵"))")
        let galleries = parseComicList(from: html)
        mlog("  parsed \(galleries.count) galleries")
        let totalPages = parseTotalPages(from: html) ?? 1
        mlog("  totalPages=\(totalPages)")
        if galleries.isEmpty {
            // 印出更多 HTML 片段協助 debug
            let snippet = html.components(separatedBy: "<li").prefix(4).joined(separator: "<li")
            mlog("  html li snippet: \(String(snippet.prefix(800)).replacingOccurrences(of: "\n", with: "↵"))")
        }
        return (galleries, totalPages)
    }

    // MARK: - 章節

    /// 取得漫畫的章節列表
    func fetchChapters(comicURL: URL) async throws -> [Chapter] {
        let html = try await fetchHTML(url: comicURL)
        return parseChapters(from: html, comicURL: comicURL)
    }

    // MARK: - 章節圖片

    /// 從章節頁面取得所有圖片 URL（使用 WKWebView 執行完整瀏覽器 JS）
    func fetchChapterImages(chapterURL: URL) async throws -> [URL] {
        mlog("fetchChapterImages url=\(chapterURL)")
        return try await MainActor.run {
            ManhuaguiWebExtractor()
        }.fetchImageURLs(chapterURL: chapterURL)
    }

    // MARK: - Networking

    private func fetchHTML(url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        mlog("  fetchHTML \(url.absoluteString) status=\(statusCode) bytes=\(data.count)")
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            mlog("  badResponse: status=\(statusCode)")
            throw ServiceError.badResponse
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    // MARK: - 解析：漫畫列表

    func parseComicList(from html: String) -> [Gallery] {
        // 實際 HTML 結構：
        // <a class="bcover" href="/comic/{id}/" title="{title}"><img src="//{thumb}" ...
        let pattern = #"href="/comic/(\d+)/"\s+title="([^"]+)"><img\s+src="(//[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var galleries: [Gallery] = []
        for m in regex.matches(in: html, range: range) {
            guard m.numberOfRanges >= 4,
                  let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html),
                  let r3 = Range(m.range(at: 3), in: html) else { continue }
            let comicID  = String(html[r1])
            let title    = String(html[r2]).htmlDecoded()
            let thumbURL = URL(string: "https:" + String(html[r3]))
            let comicURL = URL(string: "https://tw.manhuagui.com/comic/\(comicID)/")!
            galleries.append(Gallery(
                id: comicID, token: comicID, title: title,
                thumbURL: thumbURL, pageCount: nil,
                category: nil, uploader: nil,
                source: SourceID.manhuagui.rawValue,
                galleryURL: comicURL))
        }
        mlog("  parseComicList found \(galleries.count) items (pattern matches)")
        return galleries
    }

    func parseTotalPages(from html: String) -> Int? {
        // 實際 HTML：第 <strong>1</strong> / <strong>1405</strong> 頁
        if let raw = capture(pattern: #"/ <strong>(\d+)</strong> 頁"#, in: html, group: 1).first,
           let n = Int(raw) { return n }
        return nil
    }

    // MARK: - 解析：章節列表

    func parseChapters(from html: String, comicURL: URL) -> [Chapter] {
        // 從 comicURL 取出漫畫 ID，只解析當前漫畫的章節，排除側欄/推薦區其他漫畫
        // comicURL 格式：https://tw.manhuagui.com/comic/{id}/
        let comicID: String
        let pathComponents = comicURL.pathComponents  // ["", "comic", "232"]
        if pathComponents.count >= 3, pathComponents[1] == "comic" {
            comicID = pathComponents[2]
        } else {
            comicID = "\\d+"  // fallback，匹配所有（不應發生）
        }
        let pattern = "href=\"(/comic/\(comicID)/(\\d+)\\.html)\"[^>]*title=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        var chapters: [Chapter] = []
        for m in regex.matches(in: html, range: range) {
            guard m.numberOfRanges >= 4,
                  let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html),
                  let r3 = Range(m.range(at: 3), in: html) else { continue }
            let path  = String(html[r1])
            let chid  = String(html[r2])
            let title = String(html[r3]).htmlDecoded()
            guard !seen.contains(chid) else { continue }
            seen.insert(chid)
            let url = URL(string: "https://tw.manhuagui.com\(path)")!
            chapters.append(Chapter(id: chid, title: title, url: url, pageCount: nil))
        }
        // 通常依章節號排列，倒序讓最新章節排前面
        return chapters.reversed()
    }

    // MARK: - 解析：章節圖片（JSContext eval 攔截）

    func parseChapterImages(from html: String) throws -> [URL] {
        // 提取所有 <script> 內容，找含 packer（function(p,a,c,k,e,d)）的那一段
        let scriptBodies = extractScriptBodies(from: html)
        mlog("  chapter scripts count=\(scriptBodies.count), sizes=\(scriptBodies.map { $0.count })")

        let packerScript = scriptBodies.first(where: { $0.contains("function(p,a,c,k,e,d)") })
        guard let script = packerScript else {
            mlog("  no packer script found")
            mlog("  html snippet: \(String(html.prefix(500)))")
            throw ServiceError.imageDataNotFound
        }
        mlog("  found packer script len=\(script.count)")

        // 在 JSContext 直接覆蓋全域 eval，攔截 window["eval"] 及其 hex 混淆變體
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, err in mlog("  JS error: \(err?.toString() ?? "?")") }

        var captured = ""
        let captureFn: @convention(block) (String) -> Void = { code in captured = code }
        // 讓 window = this（全域物件），再把 eval 攔截掉
        // 這樣 window["eval"]、window["\x65\x76\x61\x6c"] 都會呼叫我們的攔截器
        ctx.evaluateScript("var window = this;")
        ctx.setObject(captureFn, forKeyedSubscript: "eval" as NSString)

        ctx.evaluateScript(script)
        mlog("  captured length=\(captured.count)")
        mlog("  captured snippet=\(String(captured.prefix(200)))")

        guard !captured.isEmpty else { throw ServiceError.imageDataNotFound }
        return try extractImageURLs(from: captured)
    }

    func extractScriptBodies(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*>([\s\S]*?)</script>"#) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            let s = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
    }

    func extractImageURLs(from js: String) throws -> [URL] {
        // 找 SMH.imgData({...})
        guard let start = js.range(of: "SMH.imgData("),
              let jsonStart = js.range(of: "{", range: start.upperBound..<js.endIndex) else {
            throw ServiceError.imageDataNotFound
        }
        // 找對應的右括號
        var depth = 0
        var jsonEnd = jsonStart.lowerBound
        for i in js[jsonStart.lowerBound...].indices {
            switch js[i] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { jsonEnd = js.index(after: i); break }
            default: break
            }
            if depth == 0 { break }
        }
        let jsonStr = String(js[jsonStart.lowerBound..<jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.imageDataNotFound
        }

        guard let files  = obj["files"]  as? [String],
              let path   = obj["path"]   as? String,
              let server = obj["server"] as? String else {
            throw ServiceError.imageDataNotFound
        }

        // 簽名參數 sl: { e: Int, m: String }
        let sl = obj["sl"] as? [String: Any]
        let e  = sl?["e"] as? Int
        let m  = sl?["m"] as? String

        return files.compactMap { file -> URL? in
            var urlStr = "https:" + server + path + file
            if let e = e, let m = m {
                urlStr += "?e=\(e)&m=\(m)"
            }
            return URL(string: urlStr)
        }
    }

    // MARK: - Regex Helper

    func capture(pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    // MARK: - 章節自動跳轉（供 ReaderViewModel 及 UT 使用）

    /// 解析章節標題中的集數（支援 第N集/話/回/卷，支援補零如 第01卷）
    func parseChapterNumber(from title: String) -> (num: Int, unit: String)? {
        let pattern = #"第\s*0*(\d+)\s*([集話回卷])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let nr = Range(m.range(at: 1), in: title),
              let ur = Range(m.range(at: 2), in: title),
              let num = Int(title[nr]) else { return nil }
        // 話/回 視為同類（話數型）；集/卷 視為同類（卷數型）
        let raw = String(title[ur])
        let canonical = (raw == "集" || raw == "卷") ? "卷" : "話"
        return (num, canonical)
    }

    /// 在章節列表中找上一集（故事順序，即比當前集數更舊的那一集）
    /// allChapters 是 newest-first，故事上一集 = index + 1
    func findPrevChapter(in allChapters: [Chapter], currentURL: URL) -> Chapter? {
        // fuzzy：找同單位 num-1
        if let current = allChapters.first(where: { $0.url == currentURL }),
           let (num, unit) = parseChapterNumber(from: current.title), num > 1 {
            let prevNum = num - 1
            if let found = allChapters.first(where: {
                guard let (n, u) = parseChapterNumber(from: $0.title) else { return false }
                return n == prevNum && u == unit
            }) { return found }
        }
        // index-based fallback（限同單位）
        guard let idx = allChapters.firstIndex(where: { $0.url == currentURL }) else { return nil }
        let prevIdx = idx + 1   // newest-first → 故事上一集 = 較大的 index
        guard prevIdx < allChapters.count else { return nil }
        let current = allChapters[idx]
        let candidate = allChapters[prevIdx]
        let curUnit = parseChapterNumber(from: current.title)?.unit
        let canUnit = parseChapterNumber(from: candidate.title)?.unit
        if let cu = curUnit, let cau = canUnit { return cu == cau ? candidate : nil }
        if curUnit != nil || canUnit != nil { return nil }
        return candidate
    }

    /// 在章節列表中找下一集（故事順序）
    /// - allChapters: newest-first 排列（parseChapters 輸出）
    /// - currentURL:  目前章節 URL
    /// 策略：1. fuzzy +1 同單位  2. index-1 同單位  3. nil
    func findNextChapter(in allChapters: [Chapter], currentURL: URL) -> Chapter? {
        // fuzzy：找同單位 num+1 的章節
        if let current = allChapters.first(where: { $0.url == currentURL }),
           let (num, unit) = parseChapterNumber(from: current.title) {
            let nextNum = num + 1
            if let found = allChapters.last(where: {
                guard let (n, u) = parseChapterNumber(from: $0.title) else { return false }
                return n == nextNum && u == unit
            }) { return found }
        }
        // index-based fallback（限同單位）
        guard let idx = allChapters.firstIndex(where: { $0.url == currentURL }) else { return nil }
        let nextIdx = idx - 1
        guard nextIdx >= 0 else { return nil }
        let current = allChapters[idx]
        let candidate = allChapters[nextIdx]
        let curUnit = parseChapterNumber(from: current.title)?.unit
        let canUnit = parseChapterNumber(from: candidate.title)?.unit
        if let cu = curUnit, let cau = canUnit { return cu == cau ? candidate : nil }
        if curUnit != nil || canUnit != nil { return nil }
        return candidate
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case badResponse, imageDataNotFound
        var errorDescription: String? {
            switch self {
            case .badResponse:     return "伺服器回應錯誤"
            case .imageDataNotFound: return "找不到圖片資料"
            }
        }
    }
}

// MARK: - String HTML 解碼

private extension String {
    func htmlDecoded() -> String {
        var s = self
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (e, r) in entities { s = s.replacingOccurrences(of: e, with: r) }
        return s
    }
}
