import Foundation

final class CopymangaSource: ComicSource {
    static let shared = CopymangaSource()
    private init() {}

    let sourceID: SourceID = .copymanga
    let supportsSearch      = true
    let hasChapters         = true
    let defaultFilters: [String: String] = ["sort": "-datetime_updated"]

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "-datetime_updated", label: "最近更新"),
                FilterOption(id: "-popular",          label: "最多人氣"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let sort = filters["sort"] ?? "-datetime_updated"
        let (galleries, total) = try await CopymangaService.shared.fetchList(page: page, search: search, ordering: sort)
        let limit = 20
        let totalPages = max(1, Int(ceil(Double(total) / Double(limit))))
        return ListPage(galleries: galleries, currentPage: page, totalPages: totalPages,
                        totalResults: total, nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await CopymangaService.shared.fetchChapters(pathWord: gallery.id)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        // URL: https://www.copymanga.site/comic/{pathWord}/chapter/{uuid}
        let components = url.pathComponents  // ["", "comic", pathWord, "chapter", uuid]
        guard components.count >= 5 else { throw ComicServiceError.invalidURL }
        let pathWord    = components[2]
        let chapterUUID = components[4]
        return try await CopymangaService.shared.fetchImageURLs(pathWord: pathWord, chapterUUID: chapterUUID)
    }

    func fetchImageData(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(ComicServiceConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.copymanga.site", forHTTPHeaderField: "Referer")
        let (data, response) = try await CopymangaService.shared.session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ComicServiceError.badResponse
        }
        return data
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        try? await CopymangaService.shared.fetchGalleryDetail(pathWord: gallery.id)
    }
}
