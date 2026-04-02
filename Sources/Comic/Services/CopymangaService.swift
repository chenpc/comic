import Foundation

// 拷貝漫畫 API v3
final class CopymangaService: ComicService {
    static let shared = CopymangaService()
    private init() {}

    private let apiBase = "https://api.copymanga.tv"
    let referer = "https://www.copymanga.site"

    let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "platform":   "1",
            "version":    "2024.01.01",
        ]
        return URLSession(configuration: cfg)
    }()

    // MARK: - 列表 / 搜尋

    /// ordering: "-datetime_updated" | "-popular"
    func fetchList(page: Int, search: String, ordering: String) async throws -> (galleries: [Gallery], total: Int) {
        let limit  = 20
        let offset = (page - 1) * limit
        var comps: URLComponents
        if search.isEmpty {
            comps = URLComponents(string: "\(apiBase)/api/v3/comics")!
            comps.queryItems = [
                .init(name: "ordering", value: ordering),
                .init(name: "limit",    value: "\(limit)"),
                .init(name: "offset",   value: "\(offset)"),
                .init(name: "_update",  value: "true"),
            ]
        } else {
            comps = URLComponents(string: "\(apiBase)/api/v3/search/comic")!
            comps.queryItems = [
                .init(name: "platform", value: "3"),
                .init(name: "q",        value: search),
                .init(name: "limit",    value: "\(limit)"),
                .init(name: "offset",   value: "\(offset)"),
            ]
        }
        let json = try await fetchHTML(url: comps.url!)
        return try parseGalleryList(json: json)
    }

    // MARK: - 章節列表

    func fetchChapters(pathWord: String) async throws -> [Chapter] {
        var all: [Chapter] = []
        var offset = 0
        let limit  = 500
        while true {
            var comps = URLComponents(string: "\(apiBase)/api/v3/comic/\(pathWord)/group/default/chapters")!
            comps.queryItems = [
                .init(name: "limit",   value: "\(limit)"),
                .init(name: "offset",  value: "\(offset)"),
                .init(name: "_update", value: "true"),
            ]
            let json = try await fetchHTML(url: comps.url!)
            let (chapters, total) = try parseChapterList(json: json, pathWord: pathWord)
            all.append(contentsOf: chapters)
            offset += limit
            if all.count >= total || chapters.isEmpty { break }
        }
        return all
    }

    // MARK: - 章節圖片

    func fetchImageURLs(pathWord: String, chapterUUID: String) async throws -> [URL] {
        let url = URL(string: "\(apiBase)/api/v3/comic/\(pathWord)/chapter2/\(chapterUUID)?_update=true")!
        let json = try await fetchHTML(url: url)
        return try parseImageURLs(json: json)
    }

    // MARK: - 漫畫詳細

    func fetchGalleryDetail(pathWord: String) async throws -> GalleryDetail {
        let url  = URL(string: "\(apiBase)/api/v3/comic2/\(pathWord)?_update=true")!
        let json = try await fetchHTML(url: url)
        return try parseGalleryDetail(json: json)
    }

    // MARK: - JSON 解析

    func parseGalleryList(json: String) throws -> (galleries: [Gallery], total: Int) {
        guard let data    = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code    = obj["code"] as? Int, code == 200,
              let results = obj["results"] as? [String: Any],
              let list    = results["list"] as? [[String: Any]],
              let total   = results["total"] as? Int else {
            throw ComicServiceError.parseError
        }
        let galleries: [Gallery] = list.compactMap { item in
            guard let name     = item["name"]      as? String,
                  let pathWord = item["path_word"] as? String else { return nil }
            let cover    = item["cover"]   as? String
            let thumbURL = cover.flatMap { URL(string: $0) }
            let galleryURL = URL(string: "https://www.copymanga.site/comic/\(pathWord)")!
            return Gallery(id: pathWord, token: pathWord, title: name,
                           thumbURL: thumbURL, pageCount: nil, category: nil,
                           uploader: nil, source: SourceID.copymanga.rawValue,
                           galleryURL: galleryURL)
        }
        return (galleries, total)
    }

    func parseChapterList(json: String, pathWord: String) throws -> (chapters: [Chapter], total: Int) {
        guard let data    = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code    = obj["code"] as? Int, code == 200,
              let results = obj["results"] as? [String: Any],
              let list    = results["list"] as? [[String: Any]],
              let total   = results["total"] as? Int else {
            throw ComicServiceError.parseError
        }
        let chapters: [Chapter] = list.compactMap { item in
            guard let uuid = item["uuid"] as? String,
                  let name = item["name"] as? String else { return nil }
            let size = item["size"] as? Int
            // 章節 URL 存 pathWord + uuid，fetchImageURLs 再解析
            let url = URL(string: "https://www.copymanga.site/comic/\(pathWord)/chapter/\(uuid)")!
            return Chapter(id: uuid, title: name, url: url, pageCount: size)
        }
        return (chapters, total)
    }

    func parseImageURLs(json: String) throws -> [URL] {
        guard let data    = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code    = obj["code"] as? Int, code == 200,
              let results = obj["results"] as? [String: Any],
              let chapter = results["chapter"] as? [String: Any],
              let contents = chapter["contents"] as? [[String: Any]] else {
            throw ComicServiceError.parseError
        }
        return contents.compactMap { item in
            (item["url"] as? String).flatMap { URL(string: $0) }
        }
    }

    func parseGalleryDetail(json: String) throws -> GalleryDetail {
        guard let data    = json.data(using: .utf8),
              let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code    = obj["code"] as? Int, code == 200,
              let results = obj["results"] as? [String: Any],
              let comic   = results["comic"] as? [String: Any] else {
            throw ComicServiceError.parseError
        }
        let brief  = comic["brief"] as? String
        let statusObj = comic["status"] as? [String: Any]
        let status = statusObj?["display"] as? String
        let authorArr = comic["author"] as? [[String: Any]] ?? []
        let authors: [String] = authorArr.compactMap { $0["name"] as? String }
        let themeArr = comic["theme"] as? [[String: Any]] ?? []
        let tags: [String] = themeArr.compactMap { $0["name"] as? String }
        return GalleryDetail(
            author:      authors.isEmpty ? nil : authors.joined(separator: ", "),
            description: brief,
            tags:        tags.isEmpty ? nil : tags,
            status:      status
        )
    }
}
