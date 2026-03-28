import Foundation
import JavaScriptCore
import os.log

final class ManhuarenService {
    static let shared = ManhuarenService()

    private let log = Logger(subsystem: "com.chenpc.comic", category: "ManhuarenService")
    private let base = "https://www.manhuaren.com"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Referer":    "https://www.manhuaren.com/",
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - 列表 / 搜尋

    func fetchComicList(page: Int, search: String, slug: String) async throws -> (galleries: [Gallery], totalPages: Int) {
        let url: URL
        if !search.isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            url = URL(string: "\(base)/search/?title=\(encoded)&language=1&page=\(page)")!
        } else if slug.isEmpty {
            url = URL(string: "\(base)/manhua-list/?page=\(page)")!
        } else {
            url = URL(string: "\(base)/\(slug)/?page=\(page)")!
        }
        log.info("fetchComicList url=\(url)")
        let html = try await fetchHTML(url: url)
        let galleries = parseGalleryList(from: html)
        // 沒有明確的 totalPages，用 pagesize 估算
        let pageSize = parseJSVar("pagesize", from: html).flatMap(Int.init) ?? 21
        let totalPages = galleries.count >= pageSize ? page + 1 : page
        return (galleries, totalPages)
    }

    // MARK: - 章節列表

    func fetchChapters(galleryURL: URL) async throws -> [Chapter] {
        let html = try await fetchHTML(url: galleryURL)
        return parseChapters(from: html)
    }

    // MARK: - 章節圖片

    func fetchChapterImages(chapterURL: URL) async throws -> [URL] {
        log.info("fetchChapterImages url=\(chapterURL)")
        let html = try await fetchHTML(url: chapterURL)
        return try extractImages(from: html)
    }

    // MARK: - HTML 下載

    private func fetchHTML(url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MHRError.badResponse
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - 解析：列表

    func parseGalleryList(from html: String) -> [Gallery] {
        // 搜尋頁：book-list-cover  href="/manhua-xxx/" title="xxx"><img src="...">
        // 分類頁：manga-list-2      href="/manhua-xxx/?from=..."
        var galleries: [Gallery] = []

        // 搜尋頁格式
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

        // 分類/列表頁格式：封面與標題分兩個 block，用整體 li 解析
        let liPattern = #"<li>.*?href="(/manhua-[^"?]+)(?:\?[^"]*)?"[^>]*>.*?manga-list-2-cover-img[^>]*src="(https?://[^"]+)".*?manga-list-2-title[^>]*>\s*<a[^>]*>([^<]+)</a>"#
        if let regex = try? NSRegularExpression(pattern: liPattern, options: .dotMatchesLineSeparators) {
            let range = NSRange(html.startIndex..., in: html)
            for m in regex.matches(in: html, range: range) {
                guard let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let r3 = Range(m.range(at: 3), in: html) else { continue }
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
        }
        return galleries
    }

    // MARK: - 解析：章節

    func parseChapters(from html: String) -> [Chapter] {
        // <a href="/m{id}/" title="..." class="chapteritem">第xxx话</a>
        let pattern = #"href="(/m(\d+)/)"[^>]*class="chapteritem"[^>]*>([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var chapters: [Chapter] = []
        for m in regex.matches(in: html, range: range) {
            guard let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html),
                  let r3 = Range(m.range(at: 3), in: html) else { continue }
            let path  = String(html[r1])
            let cid   = String(html[r2])
            let title = String(html[r3]).mhrHTMLDecoded().trimmingCharacters(in: .whitespaces)
            let url   = URL(string: "\(base)\(path)")!
            chapters.append(Chapter(id: cid, title: title, url: url, pageCount: nil))
        }
        // 頁面是倒序（最新在前），反轉為正序
        return chapters.reversed()
    }

    // MARK: - 解析：章節圖片（解碼 JS packer）

    func extractImages(from html: String) throws -> [URL] {
        // 找包含 newImgs 的 <script> 標籤（可能是 packer 或明文）
        let scriptPattern = #"<script[^>]*>\s*((?:eval\(function|var\s+newImgs)[^<]+)\s*</script>"#
        guard let regex = try? NSRegularExpression(pattern: scriptPattern, options: .dotMatchesLineSeparators),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else {
            log.warning("extractImages: 找不到包含 newImgs 的 script")
            throw MHRError.parseError
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
            throw MHRError.parseError
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

    enum MHRError: LocalizedError {
        case badResponse, parseError
        var errorDescription: String? {
            switch self {
            case .badResponse: return "伺服器回應錯誤"
            case .parseError:  return "解析頁面失敗"
            }
        }
    }
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
