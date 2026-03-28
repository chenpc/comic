import Foundation


final class EHentaiService {
    static let shared = EHentaiService()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// 取得圖庫清單
    /// - Parameters:
    ///   - next: cursor（上一頁回傳的 nextCursor），nil 代表第一頁
    ///   - search: 搜尋關鍵字
    ///   - fCats: 分類 bitmask
    /// - Returns: (圖庫列表, nextCursor, 總筆數)
    func fetchGalleryList(next: String? = nil, search: String = "", fCats: Int = 0) async throws -> (galleries: [Gallery], nextCursor: String?, totalResults: Int) {
        var components = URLComponents(string: "https://e-hentai.org/")!
        var queryItems: [URLQueryItem] = []
        if let next   { queryItems.append(URLQueryItem(name: "next",     value: next)) }
        if !search.isEmpty { queryItems.append(URLQueryItem(name: "f_search", value: search)) }
        if fCats > 0  { queryItems.append(URLQueryItem(name: "f_cats",   value: "\(fCats)")) }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        let html = try await fetchHTML(url: components.url!)
        var galleries = parseGalleryList(from: html)
        if !galleries.isEmpty {
            galleries = try await enrichWithAPI(galleries: galleries)
        }
        let nextCursor = parseNextCursor(from: html)
        let total = parseTotalResults(from: html) ?? 0
        return (galleries, nextCursor, total)
    }

    /// 解析下一頁 cursor（?next=gid 或 &next=gid 或 &amp;next=gid）
    func parseNextCursor(from html: String) -> String? {
        // <a id="unext" href="https://e-hentai.org/?next=XXXXXXX">
        // 搜尋時可能是 ?f_search=...&next=... 或 &amp;next=...
        capture(pattern: #"[?&](?:amp;)?next=(\d+)"#, in: html, group: 1).first
    }

    /// 解析總筆數（用來估算總頁數）
    func parseTotalResults(from html: String) -> Int? {
        // 找形如 "1,234,567" 後面接 " result" 的數字
        guard let raw = capture(pattern: #"([\d,]+)\s+result"#, in: html, group: 1).first else { return nil }
        return Int(raw.replacingOccurrences(of: ",", with: ""))
    }

    /// 呼叫 e-hentai gdata API 取得縮圖等詳細資訊
    private func enrichWithAPI(galleries: [Gallery]) async throws -> [Gallery] {
        let gidlist = galleries.map { [Int($0.id) ?? 0, $0.token] as [Any] }
        let body: [String: Any] = ["method": "gdata", "gidlist": gidlist, "namespace": 1]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.e-hentai.org/api.php")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gmetadata = json["gmetadata"] as? [[String: Any]] else {
            return galleries
        }

        var metaMap: [String: [String: Any]] = [:]
        for meta in gmetadata {
            if let gid = meta["gid"] { metaMap["\(gid)"] = meta }
        }

        return galleries.map { g in
            guard let meta = metaMap[g.id] else { return g }
            let thumb = (meta["thumb"] as? String).flatMap { URL(string: $0) }
            let filecount = (meta["filecount"] as? String).flatMap { Int($0) }
            return Gallery(id: g.id, token: g.token, title: g.title,
                           thumbURL: thumb, pageCount: filecount ?? g.pageCount,
                           category: meta["category"] as? String,
                           uploader: meta["uploader"] as? String)
        }
    }

    /// 從圖庫頁面取得所有圖片頁面網址（處理分頁）
    func fetchImagePageURLs(galleryURL: URL) async throws -> [String] {
        var allURLs: [String] = []
        var currentURL: URL? = galleryURL

        while let url = currentURL {
            let html = try await fetchHTML(url: url)
            let urls = parseImagePageURLs(from: html)
            allURLs.append(contentsOf: urls)
            currentURL = parseNextGalleryPage(from: html)
        }

        return allURLs.uniqued()
    }

    /// 從圖庫頁面取得標題
    func fetchGalleryTitle(galleryURL: URL) async throws -> String {
        let html = try await fetchHTML(url: galleryURL)
        return parseGalleryTitle(from: html) ?? galleryURL.lastPathComponent
    }

    /// 從圖片頁面取得實際圖片網址
    func fetchImageURL(pageURL: String) async throws -> URL {
        guard let url = URL(string: pageURL) else {
            throw ServiceError.invalidURL
        }
        let html = try await fetchHTML(url: url)
        guard let imageURLString = parseImageURL(from: html),
              let imageURL = URL(string: imageURLString) else {
            throw ServiceError.imageNotFound
        }
        return imageURL
    }

    /// 下載圖片資料
    /// - Parameter referer: 覆蓋 Referer header；nil 則用圖片 host 作為 Referer
    func fetchImageData(url: URL, referer: String? = nil) async throws -> Data {
        var request = makeRequest(url: url)
        let ref = referer ?? url.host.map { "https://\($0)" } ?? "https://e-hentai.org"
        request.setValue(ref, forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Networking

    func fetchHTML(url: URL) async throws -> String {
        let request = makeRequest(url: url)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.badResponse
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://e-hentai.org", forHTTPHeaderField: "Referer")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    // MARK: - HTML Parsing

    func parseGalleryList(from html: String) -> [Gallery] {
        // 解析各種顯示模式的圖庫連結
        // URL 格式: https://e-hentai.org/g/{gid}/{token}/
        let linkPattern = #"href="https://e-hentai\.org/g/(\d+)/([a-f0-9]+)/""#
        let links = captureMultiple(pattern: linkPattern, in: html, groups: [1, 2])

        // 找縮圖：<img ... src="https://..." ...> 在連結附近
        // 用更簡單方式：抓所有 gl item 的縮圖
        let thumbPattern = #"<img[^>]+src="(https://[^"]+ehgt\.org[^"]+|https://[^"]+\.e-hentai\.org[^"]+)"[^>]*>"#
        let thumbURLs = capture(pattern: thumbPattern, in: html, group: 1)

        // 抓標題：glink class 內的文字
        let titlePattern = #"<div class="glink">([^<]+)</div>"#
        let titles = capture(pattern: titlePattern, in: html, group: 1)

        // 抓頁數：以 p 結尾的數字
        let pagePattern = #"(\d+) page"#
        let pageCounts = capture(pattern: pagePattern, in: html, group: 1)

        // 抓分類
        let categoryPattern = #"<div class="cs?[^"]*"[^>]*>([^<]+)</div>"#
        let categories = capture(pattern: categoryPattern, in: html, group: 1)

        var galleries: [Gallery] = []
        for (i, pair) in links.enumerated() {
            guard pair.count == 2 else { continue }
            let gid = pair[0], token = pair[1]
            let title = i < titles.count ? titles[i] : "Gallery \(gid)"
            let thumb = i < thumbURLs.count ? URL(string: thumbURLs[i]) : nil
            let pages = i < pageCounts.count ? Int(pageCounts[i]) : nil
            let category = i < categories.count ? categories[i] : nil
            galleries.append(Gallery(id: gid, token: token, title: title,
                                     thumbURL: thumb, pageCount: pages,
                                     category: category, uploader: nil))
        }
        return galleries
    }

    func parseImagePageURLs(from html: String) -> [String] {
        // 圖片頁面連結格式：https://e-hentai.org/s/{hash}/{gid}-{page}
        return matches(pattern: #"https://e-hentai\.org/s/[a-f0-9]+/\d+-\d+"#, in: html)
    }

    func parseNextGalleryPage(from html: String) -> URL? {
        // 找下一頁按鈕：<a href="...?p=N">&gt;</a>
        let results = capture(pattern: #"href="([^"]+)"[^>]*>&gt;<"#, in: html, group: 1)
        return results.first.flatMap { URL(string: $0) }
    }

    func parseGalleryTitle(from html: String) -> String? {
        // <h1 id="gn">標題</h1>
        return capture(pattern: #"<h1 id="gn">([^<]+)</h1>"#, in: html, group: 1).first
            ?? capture(pattern: #"<h1 id="gj">([^<]+)</h1>"#, in: html, group: 1).first
    }

    func parseImageURL(from html: String) -> String? {
        // <img id="img" src="URL" ...>
        return capture(pattern: #"<img\s+id="img"\s+src="([^"]+)""#, in: html, group: 1).first
            ?? capture(pattern: #"id="img"[^>]+src="([^"]+)""#, in: html, group: 1).first
    }

    // MARK: - Regex Helpers

    func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    func captureMultiple(pattern: String, in text: String, groups: [Int]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            var result: [String] = []
            for g in groups {
                guard match.numberOfRanges > g,
                      let r = Range(match.range(at: g), in: text) else { return nil }
                result.append(String(text[r]))
            }
            return result
        }
    }

    func capture(pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    // MARK: - Errors

    enum ServiceError: Error, LocalizedError {
        case badResponse
        case invalidURL
        case imageNotFound

        var errorDescription: String? {
            switch self {
            case .badResponse: return "伺服器回應錯誤"
            case .invalidURL: return "無效的網址"
            case .imageNotFound: return "找不到圖片"
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
