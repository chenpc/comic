import Foundation
import JavaScriptCore
import os.log

private let mhrLogURL = URL(fileURLWithPath: "/tmp/comic_mhr.log")
private func mhrlog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: mhrLogURL.path),
           let fh = try? FileHandle(forWritingTo: mhrLogURL) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: mhrLogURL)
        }
    }
}

final class ManhuarenService: ComicService {
    static let shared = ManhuarenService()

    private let log = Logger(subsystem: "com.chenpc.comic", category: "ManhuarenService")
    private let base = "https://www.manhuaren.com"

    let session: URLSession
    let referer = "https://www.manhuaren.com/"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    // MARK: - 列表 / 搜尋

    func fetchComicList(page: Int, search: String, slug: String, paramOverrides: [String: String] = [:]) async throws -> (galleries: [Gallery], totalPages: Int) {
        if !search.isEmpty {
            return try await fetchSearch(page: page, search: search)
        }
        if !paramOverrides.isEmpty {
            // 有篩選條件：全部走 AJAX（含第 1 頁），確保所有 params 都生效
            // 以預設值為基礎，疊加 paramOverrides，不污染 ajaxParams 共享狀態
            mhrlog("fetchComicList AJAX page=\(page) overrides=\(paramOverrides)")
            return try await fetchAJAXPage(page: page, overrides: paramOverrides)
        }
        // 無篩選：第 1 頁用 HTML 解析，第 2 頁以後走 AJAX
        if page == 1 {
            let pageURL = URL(string: "\(base)/manhua-list/")!
            mhrlog("fetchComicList HTML page=1 url=\(pageURL)")
            let html = try await fetchHTML(url: pageURL)
            ajaxParams = parseAJAXParams(from: html, slug: "")
            mhrlog("  ajaxParams sort=\(ajaxParams["sort"] ?? "?")")
            let galleries = parseGalleryList(from: html)
            mhrlog("  parsed \(galleries.count) galleries, first=\(galleries.first?.title ?? "-")")
            return (galleries, galleries.isEmpty ? 1 : page + 1)
        } else {
            return try await fetchAJAXPage(page: page)
        }
    }

    /// 儲存無篩選時第 1 頁解析到的 AJAX 基底參數（供無篩選翻頁使用）
    private var ajaxParams: [String: String] = [:]

    private static let defaultAJAXParams: [String: String] = [
        "categoryid": "0", "tagid": "0", "status": "0",
        "usergroup": "0", "pay": "-1", "areaid": "0",
        "sort": "10", "iscopyright": "0",
    ]

    private func fetchSearch(page: Int, search: String) async throws -> ([Gallery], Int) {
        let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
        let url = URL(string: "\(base)/search/?title=\(encoded)&language=1&page=\(page)")!
        log.info("fetchSearch url=\(url)")
        let html = try await fetchHTML(url: url)
        let galleries = parseGalleryList(from: html, isSearch: true)
        return (galleries, galleries.isEmpty ? page : page + 1)
    }

    private func fetchAJAXPage(page: Int, overrides: [String: String] = [:]) async throws -> ([Gallery], Int) {
        var req = URLRequest(url: URL(string: "\(base)/dm5.ashx?d=\(Date().timeIntervalSince1970)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // 基底：有 overrides 時用預設值，否則用 HTML 解析到的 ajaxParams
        var params = overrides.isEmpty ? ajaxParams : Self.defaultAJAXParams
        for (k, v) in overrides { params[k] = v }
        params["action"] = "getclasscomics"
        params["pageindex"] = "\(page)"
        params["pagesize"] = "21"
        let body = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        log.info("fetchAJAXPage page=\(page) params=\(params)")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ComicServiceError.badResponse
        }
        let galleries = try parseAJAXResponse(data: data)
        return (galleries, galleries.isEmpty ? page : page + 1)
    }

    func parseAJAXParams(from html: String, slug: String) -> [String: String] {
        var params: [String: String] = [
            "categoryid": "0", "tagid": "0", "status": "0",
            "usergroup": "0", "pay": "-1", "areaid": "0",
            "sort": "10", "iscopyright": "0"
        ]
        for key in ["categoryid", "tagid", "status", "usergroup", "pay", "areaid", "sort"] {
            if let v = parseJSVar(key, from: html) { params[key] = v }
        }
        if let copy = parseJSVar("iscopyright", from: html) {
            params["iscopyright"] = copy.lowercased() == "true" ? "1" : "0"
        }
        return params
    }

    func parseAJAXResponse(data: Data) throws -> [Gallery] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["UpdateComicItems"] as? [[String: Any]] else {
            throw ComicServiceError.parseError
        }
        return items.compactMap { item in
            guard let key   = item["UrlKey"]       as? String,
                  let title = item["Title"]        as? String else { return nil }
            let thumb = (item["ShowPicUrlB"] as? String).flatMap(URL.init)
            let gURL  = URL(string: "\(base)/\(key)/")!
            return Gallery(id: key, token: key, title: title.mhrHTMLDecoded(),
                           thumbURL: thumb, pageCount: nil, category: nil,
                           uploader: nil, source: SourceID.manhuaren.rawValue,
                           galleryURL: gURL)
        }
    }

    // MARK: - 章節列表 + 詳細資料

    func fetchChapters(galleryURL: URL) async throws -> [Chapter] {
        let html = try await fetchHTML(url: galleryURL)
        return parseChapters(from: html)
    }

    func fetchGalleryDetail(galleryURL: URL) async -> GalleryDetail? {
        guard let html = try? await fetchHTML(url: galleryURL) else { return nil }
        return parseGalleryDetail(from: html)
    }

    func parseGalleryDetail(from html: String) -> GalleryDetail? {
        // 作者解析：兩步驟策略
        // 步驟1：找出包含「作者」的段落（允許 <> 在內）
        // 步驟2：從段落中取最後一個 >TEXT</a> 的文字
        var author: String?
        let authorSectionPatterns: [(String, NSRegularExpression.Options)] = [
            (#"作者[：:].{0,300}?</a>"#,         .dotMatchesLineSeparators),   // 作者：...<a>NAME</a>
            (#"<em>作者</em>.{0,300}?</a>"#,     .dotMatchesLineSeparators),   // <em>作者</em>...<a>NAME</a>
            (#"作者</[a-z]+>.{0,300}?</a>"#,     .dotMatchesLineSeparators),   // 作者</span>...<a>NAME</a>
        ]
        outer: for (pattern, opts) in authorSectionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts),
                  let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let sectionRange = Range(m.range(at: 0), in: html) else { continue }
            let section = String(html[sectionRange])
            // 在段落裡找所有 >TEXT</a>，取第一個非空的
            guard let nameRegex = try? NSRegularExpression(pattern: #">([^<>]+)</a>"#) else { continue }
            let ns = NSRange(section.startIndex..., in: section)
            for nm in nameRegex.matches(in: section, range: ns) {
                guard let nr = Range(nm.range(at: 1), in: section) else { continue }
                let name = String(section[nr]).mhrHTMLDecoded().trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    author = name
                    break outer
                }
            }
        }

        // 簡介：常見 class="detail-desc" 或在「簡介」標題後面
        var description: String?
        let descPatterns = [
            #"class="detail-desc[^"]*"[^>]*>\s*([\s\S]{10,500}?)\s*(?:</p>|</div>)"#,
            #"class="detail-introduction[^"]*"[^>]*>\s*([\s\S]{10,500}?)\s*</div>"#,
            #"簡介[：:]\s*</[^>]+>\s*<[^>]+>\s*([\s\S]{10,500}?)\s*<"#,
        ]
        for pattern in descPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                let raw = String(html[r])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .mhrHTMLDecoded()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.count > 5 {
                    description = raw
                    break
                }
            }
        }

        guard author != nil || description != nil else { return nil }
        return GalleryDetail(author: author, description: description)
    }

    // MARK: - 章節圖片

    func fetchChapterImages(chapterURL: URL) async throws -> [URL] {
        log.info("fetchChapterImages url=\(chapterURL)")
        let html = try await fetchHTML(url: chapterURL)
        return try extractImages(from: html)
    }

    // MARK: - 解析：列表

    func parseGalleryList(from html: String, isSearch: Bool = false) -> [Gallery] {
        var galleries: [Gallery] = []

        // 搜尋頁格式：只在真正搜尋結果頁才用（避免分類頁的導覽連結誤匹配）
        if isSearch {
            let searchPattern = #"href="(/manhua-[^"?]+/)"[^>]*title="([^"]+)"[^>]*>\s*<img[^>]+src="(https?://[^"]+)""#
            if let regex = try? NSRegularExpression(pattern: searchPattern) {
                let range = NSRange(html.startIndex..., in: html)
                for m in regex.matches(in: html, range: range) {
                    guard let r1 = Range(m.range(at: 1), in: html),
                          let r2 = Range(m.range(at: 2), in: html),
                          let r3 = Range(m.range(at: 3), in: html) else { continue }
                    let path  = String(html[r1])
                    let title = String(html[r2]).mhrHTMLDecoded()
                    let thumb = URL(string: String(html[r3]))
                    let slug  = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let gURL  = URL(string: "\(base)\(path)")!
                    galleries.append(Gallery(id: slug, token: slug, title: title,
                                             thumbURL: thumb, pageCount: nil, category: nil,
                                             uploader: nil, source: SourceID.manhuaren.rawValue,
                                             galleryURL: gURL))
                }
            }
            if !galleries.isEmpty { return galleries }
        }

        // 分類/列表頁格式：分兩步抓 href 與 title，按順序配對
        // step1: 從 manga-list-2-cover-img 取 href + thumb
        let coverPattern = #"href="(/manhua-[^"?]+)[^"]*">[^<]*<img[^>]+class="manga-list-2-cover-img"[^>]+src="(https?://[^"]+)""#
        // step2: 從 manga-list-2-title 取 title
        let titlePattern = #"class="manga-list-2-title"[^>]*>\s*<a[^>]*>([^<]+)</a>"#

        guard let coverReg = try? NSRegularExpression(pattern: coverPattern),
              let titleReg = try? NSRegularExpression(pattern: titlePattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let covers = coverReg.matches(in: html, range: range)
        let titles = titleReg.matches(in: html, range: range)
        guard !covers.isEmpty else { return [] }
        let count = min(covers.count, titles.count)

        for (cover, titleMatch) in zip(covers.prefix(count), titles.prefix(count)) {
            guard let r1 = Range(cover.range(at: 1), in: html),
                  let r2 = Range(cover.range(at: 2), in: html),
                  let r3 = Range(titleMatch.range(at: 1), in: html) else { continue }
            let path  = String(html[r1])
            let thumb = URL(string: String(html[r2]))
            let title = String(html[r3]).mhrHTMLDecoded()
            let slug  = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let gURL  = URL(string: "\(base)\(path)")!
            galleries.append(Gallery(id: slug, token: slug, title: title,
                                     thumbURL: thumb, pageCount: nil, category: nil,
                                     uploader: nil, source: SourceID.manhuaren.rawValue,
                                     galleryURL: gURL))
        }
        return galleries
    }

    // MARK: - 解析：章節

    func parseChapters(from html: String) -> [Chapter] {
        // 結構1（新版）：<a href="/m{id}/" class="chapteritem">...<p class="detail-list-2-info-title">{title}</p>...</a>
        // 結構2（舊版）：<a href="/m{id}/" class="chapteritem">{title}</a>
        let blockPattern = #"<a\s+href="(/m(\d+)/)"[^>]*class="chapteritem"[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: blockPattern) else { return [] }
        let titleRegex = try? NSRegularExpression(pattern: #"detail-list-2-info-title">([^<]+)<"#)
        let range = NSRange(html.startIndex..., in: html)
        var chapters: [Chapter] = []
        for m in regex.matches(in: html, range: range) {
            guard let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html),
                  let r3 = Range(m.range(at: 3), in: html) else { continue }
            let path  = String(html[r1])
            let cid   = String(html[r2])
            let block = String(html[r3])
            // 先嘗試從 detail-list-2-info-title 取標題，找不到則直接用 block 文字
            var title: String
            let blockNS = NSRange(block.startIndex..., in: block)
            if let tm = titleRegex?.firstMatch(in: block, range: blockNS),
               let tr = Range(tm.range(at: 1), in: block) {
                title = String(block[tr]).mhrHTMLDecoded().trimmingCharacters(in: .whitespaces)
            } else {
                title = block.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .mhrHTMLDecoded().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !title.isEmpty else { continue }
            // 付費鎖定章節：含有 detail-list-2-info-right 鎖頭圖示
            if block.contains("detail-list-2-info-right") {
                title = "$$ " + title
            }
            let url = URL(string: "\(base)\(path)")!
            chapters.append(Chapter(id: cid, title: title, url: url, pageCount: nil))
        }
        // 頁面是倒序（最新在前），反轉為正序
        return chapters.reversed()
    }

    // MARK: - 解析：章節圖片（解碼 JS packer）

    func extractImages(from html: String) throws -> [URL] {
        // 找包含 newImgs 的 <script> 標籤（可能是 packer 或明文）
        // 注意：packed JS 本身含有 < 字元（如 c<a），所以不能用 [^<]+ 而要用 .*?
        let scriptPattern = #"<script[^>]*>\s*((?:eval\(function|var\s+newImgs).*?)\s*</script>"#
        guard let regex = try? NSRegularExpression(pattern: scriptPattern, options: .dotMatchesLineSeparators),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else {
            log.warning("extractImages: 找不到包含 newImgs 的 script")
            throw ComicServiceError.parseError
        }
        let packedJS = String(html[r])

        // 用 JavaScriptCore 執行，取 newImgs 陣列
        let ctx = JSContext()!
        ctx.exceptionHandler = { [weak self] _, ex in
            self?.log.error("JSC exception: \(ex?.toString() ?? "?")")
        }
        ctx.evaluateScript(packedJS)
        guard let arr = ctx.objectForKeyedSubscript("newImgs"),
              arr.isArray,
              let count = arr.objectForKeyedSubscript("length")?.toInt32(),
              count > 0 else {
            log.warning("extractImages: newImgs 不存在或為空")
            throw ComicServiceError.parseError
        }
        var urls: [URL] = []
        for i in 0..<Int(count) {
            if let s = arr.objectAtIndexedSubscript(i)?.toString(),
               let u = URL(string: s) {
                urls.append(u)
            }
        }
        log.info("extractImages: \(urls.count) 張")
        return urls
    }

    // MARK: - Helpers

    private func parseJSVar(_ name: String, from html: String) -> String? {
        let pattern = "var\\s+\(name)\\s*=\\s*[\"'](.*?)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    // 向後相容 typealias
    typealias MHRError = ComicServiceError
}

private extension String {
    func mhrHTMLDecoded() -> String {
        var s = self
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (e, r) in entities { s = s.replacingOccurrences(of: e, with: r) }
        return s
    }
}
