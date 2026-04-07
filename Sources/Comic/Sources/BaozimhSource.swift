import Foundation

final class BaozimhSource: ComicSource {
    static let shared = BaozimhSource()
    private init() {}

    let sourceID: SourceID = .baozimh
    private let throttle = RequestThrottle(maxPerSecond: 1, maxRetries: 3, retryDelay: 5)
    let supportsSearch      = true
    let hasChapters         = true
    let defaultFilters: [String: String] = ["sort": "1"]

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "1", label: "最近更新"),
                FilterOption(id: "0", label: "最多人氣"),
            ]),
            FilterGroup(id: "region", label: "地區", options: [
                FilterOption(id: "",       label: "全部"),
                FilterOption(id: "japan",  label: "日漫"),
                FilterOption(id: "cn",     label: "中漫"),
                FilterOption(id: "kr",     label: "韓漫"),
            ]),
            FilterGroup(id: "status", label: "進度", options: [
                FilterOption(id: "",       label: "全部"),
                FilterOption(id: "serial", label: "連載中"),
                FilterOption(id: "pub",    label: "已完結"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let sort   = filters["sort"]   ?? "1"
        let region = filters["region"] ?? ""
        let status = filters["status"] ?? ""
        let (galleries, totalPages) = try await BaozimhService.shared.fetchList(
            page: page, search: search, region: region, status: status, sort: sort)
        return ListPage(galleries: galleries, currentPage: page, totalPages: totalPages,
                        totalResults: totalPages * 36, nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await BaozimhService.shared.fetchChapters(galleryURL: gallery.galleryURL)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        try await BaozimhService.shared.fetchImageURLs(chapterURL: url)
    }

    func fetchImageData(url: URL) async throws -> Data {
        try await throttle.fetchWithRetry {
            var req = URLRequest(url: url)
            req.setValue(ComicServiceConstants.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.baozimh.com", forHTTPHeaderField: "Referer")
            let (data, response) = try await BaozimhService.shared.session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw ComicServiceError.badResponse
            }
            return data
        }
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        try? await BaozimhService.shared.fetchGalleryDetail(galleryURL: gallery.galleryURL)
    }
}
