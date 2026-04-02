import Foundation

final class MangaDexSource: ComicSource {
    static let shared = MangaDexSource()
    private init() {}

    let sourceID: SourceID  = .mangadex
    let supportsSearch       = true
    let hasChapters          = true
    let defaultFilters: [String: String] = ["sort": "-updatedAt"]

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "-updatedAt",     label: "最近更新"),
                FilterOption(id: "-followedCount", label: "最多追蹤"),
                FilterOption(id: "-rating",        label: "最高評分"),
                FilterOption(id: "title",          label: "名稱排序"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let sort = filters["sort"] ?? "-updatedAt"
        let (galleries, total) = try await MangaDexService.shared.fetchMangaList(page: page, search: search, orderBy: sort)
        let limit = 20
        let totalPages = max(1, Int(ceil(Double(total) / Double(limit))))
        return ListPage(galleries: galleries, currentPage: page, totalPages: totalPages,
                        totalResults: total, nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await MangaDexService.shared.fetchChapters(mangaID: gallery.id)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        // URL: https://mangadex.org/chapter/{chapterID}
        let chapterID = url.lastPathComponent
        return try await MangaDexService.shared.fetchImageURLs(chapterID: chapterID)
    }

    func fetchImageData(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(ComicServiceConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://mangadex.org", forHTTPHeaderField: "Referer")
        let (data, response) = try await MangaDexService.shared.session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ComicServiceError.badResponse
        }
        return data
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        try? await MangaDexService.shared.fetchGalleryDetail(mangaID: gallery.id)
    }
}
