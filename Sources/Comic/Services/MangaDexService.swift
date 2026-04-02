import Foundation

// MangaDex REST API — 僅顯示繁體中文（zh-hk / zh）翻譯章節
final class MangaDexService: ComicService {
    static let shared = MangaDexService()
    private init() {}

    let session: URLSession = URLSession(configuration: .default)
    let referer = "https://mangadex.org"

    private let apiBase    = "https://api.mangadex.org"
    private let uploadBase = "https://uploads.mangadex.org"

    // MARK: - 漫畫列表

    func fetchMangaList(page: Int, search: String, orderBy: String, tagUUID: String = "") async throws -> (galleries: [Gallery], total: Int) {
        let limit = 20
        let offset = (page - 1) * limit
        var items: [URLQueryItem] = [
            .init(name: "limit",  value: "\(limit)"),
            .init(name: "offset", value: "\(offset)"),
            .init(name: "availableTranslatedLanguage[]", value: "zh-hk"),
            .init(name: "availableTranslatedLanguage[]", value: "zh"),
            .init(name: "includes[]", value: "cover_art"),
            .init(name: "includes[]", value: "author"),
        ]
        switch orderBy {
        case "-followedCount": items.append(.init(name: "order[followedCount]", value: "desc"))
        case "-rating":        items.append(.init(name: "order[rating]",        value: "desc"))
        case "title":          items.append(.init(name: "order[title]",         value: "asc"))
        default:               items.append(.init(name: "order[updatedAt]",     value: "desc"))
        }
        if !tagUUID.isEmpty {
            items.append(.init(name: "includedTags[]", value: tagUUID))
        }
        if !search.isEmpty {
            items.append(.init(name: "title", value: search))
        }
        var comps = URLComponents(string: "\(apiBase)/manga")!
        comps.queryItems = items
        let json = try await fetchHTML(url: comps.url!)
        return try parseMangaList(json: json)
    }

    // MARK: - 章節列表

    func fetchChapters(mangaID: String) async throws -> [Chapter] {
        var all: [Chapter] = []
        var offset = 0
        let limit = 500
        while true {
            var comps = URLComponents(string: "\(apiBase)/manga/\(mangaID)/feed")!
            comps.queryItems = [
                .init(name: "translatedLanguage[]", value: "zh-hk"),
                .init(name: "translatedLanguage[]", value: "zh"),
                .init(name: "limit",          value: "\(limit)"),
                .init(name: "offset",         value: "\(offset)"),
                .init(name: "order[volume]",  value: "asc"),
                .init(name: "order[chapter]", value: "asc"),
            ]
            let json = try await fetchHTML(url: comps.url!)
            let (chapters, total) = try parseChapters(json: json)
            all.append(contentsOf: chapters)
            offset += limit
            if all.count >= total || chapters.isEmpty { break }
        }
        return all
    }

    // MARK: - 圖片 URL

    func fetchImageURLs(chapterID: String) async throws -> [URL] {
        let url = URL(string: "\(apiBase)/at-home/server/\(chapterID)")!
        let json = try await fetchHTML(url: url)
        return try parseImageURLs(json: json)
    }

    // MARK: - 漫畫詳細

    func fetchGalleryDetail(mangaID: String) async throws -> GalleryDetail {
        var comps = URLComponents(string: "\(apiBase)/manga/\(mangaID)")!
        comps.queryItems = [
            .init(name: "includes[]", value: "author"),
            .init(name: "includes[]", value: "artist"),
        ]
        let json = try await fetchHTML(url: comps.url!)
        return try parseGalleryDetail(json: json)
    }

    // MARK: - JSON 解析

    private func parseMangaList(json: String) throws -> (galleries: [Gallery], total: Int) {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr  = obj["data"] as? [[String: Any]],
              let total = obj["total"] as? Int else {
            throw ComicServiceError.parseError
        }
        let galleries: [Gallery] = arr.compactMap { item in
            guard let id    = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any] else { return nil }
            let titleMap = attrs["title"] as? [String: String] ?? [:]
            let title = titleMap["zh-hk"] ?? titleMap["zh"] ?? titleMap["en"]
                        ?? titleMap.values.first ?? id
            let rels = item["relationships"] as? [[String: Any]] ?? []
            var coverURL: URL?
            for rel in rels {
                if rel["type"] as? String == "cover_art",
                   let relAttrs = rel["attributes"] as? [String: Any],
                   let fileName = relAttrs["fileName"] as? String {
                    coverURL = URL(string: "\(uploadBase)/covers/\(id)/\(fileName).512.jpg")
                    break
                }
            }
            let galleryURL = URL(string: "https://mangadex.org/title/\(id)")!
            return Gallery(id: id, token: id, title: title,
                           thumbURL: coverURL, pageCount: nil, category: nil,
                           uploader: nil, source: SourceID.mangadex.rawValue,
                           galleryURL: galleryURL)
        }
        return (galleries, total)
    }

    private func parseChapters(json: String) throws -> (chapters: [Chapter], total: Int) {
        guard let data  = json.data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr   = obj["data"] as? [[String: Any]],
              let total = obj["total"] as? Int else {
            throw ComicServiceError.parseError
        }
        let chapters: [Chapter] = arr.compactMap { item in
            guard let id    = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any] else { return nil }
            let volume    = attrs["volume"]  as? String
            let chapterNo = attrs["chapter"] as? String
            let titleAttr = attrs["title"]   as? String
            var label = ""
            if let vol = volume,    !vol.isEmpty    { label += "Vol.\(vol) " }
            if let ch  = chapterNo, !ch.isEmpty     { label += "第\(ch)話" }
            if label.trimmingCharacters(in: .whitespaces).isEmpty {
                label = titleAttr ?? id
            }
            let pages = attrs["pages"] as? Int
            let url = URL(string: "https://mangadex.org/chapter/\(id)")!
            return Chapter(id: id, title: label, url: url, pageCount: pages)
        }
        return (chapters, total)
    }

    private func parseImageURLs(json: String) throws -> [URL] {
        guard let data     = json.data(using: .utf8),
              let obj      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseUrl  = obj["baseUrl"] as? String,
              let chapter  = obj["chapter"] as? [String: Any],
              let hash     = chapter["hash"] as? String,
              let files    = chapter["data"] as? [String] else {
            throw ComicServiceError.parseError
        }
        return files.compactMap { URL(string: "\(baseUrl)/data/\(hash)/\($0)") }
    }

    private func parseGalleryDetail(json: String) throws -> GalleryDetail {
        guard let data  = json.data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item  = obj["data"] as? [String: Any],
              let attrs = item["attributes"] as? [String: Any] else {
            throw ComicServiceError.parseError
        }
        let descMap = attrs["description"] as? [String: String] ?? [:]
        let desc    = descMap["zh-hk"] ?? descMap["zh"] ?? descMap["en"]
        let status  = attrs["status"] as? String
        let rels    = item["relationships"] as? [[String: Any]] ?? []
        let authors: [String] = rels.compactMap { rel in
            guard rel["type"] as? String == "author",
                  let relAttrs = rel["attributes"] as? [String: Any],
                  let name     = relAttrs["name"] as? String else { return nil }
            return name
        }
        let tagObjs = attrs["tags"] as? [[String: Any]] ?? []
        let tags: [String] = tagObjs.compactMap { tag in
            let tagAttrs = tag["attributes"] as? [String: Any]
            let nameMap  = tagAttrs?["name"] as? [String: String] ?? [:]
            return nameMap["zh"] ?? nameMap["zh-hk"] ?? nameMap["en"]
        }
        return GalleryDetail(
            author:      authors.isEmpty ? nil : authors.joined(separator: ", "),
            description: desc,
            tags:        tags.isEmpty ? nil : tags,
            status:      status
        )
    }
}
