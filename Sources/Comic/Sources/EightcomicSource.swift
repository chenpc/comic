import Foundation

final class EightcomicSource: ComicSource {
    static let shared = EightcomicSource()

    let sourceID: SourceID = .eightcomic
    let supportsSearch     = true
    let hasChapters        = true
    let defaultFilters: [String: String] = ["sort": "new"]

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "category", label: "类别", options: [
                FilterOption(id: "all", label: "全部"),
                FilterOption(id: "1",   label: "格鬥系列"),
                FilterOption(id: "2",   label: "競技系列"),
                FilterOption(id: "11",  label: "少女系列"),
                FilterOption(id: "12",  label: "青春系列"),
                FilterOption(id: "13",  label: "休閑系列"),
                FilterOption(id: "21",  label: "職業系列"),
                FilterOption(id: "22",  label: "科幻懸疑"),
                FilterOption(id: "20",  label: "陸漫系列"),
            ]),
            FilterGroup(id: "status", label: "狀態", options: [
                FilterOption(id: "all",      label: "全部"),
                FilterOption(id: "ongoing",  label: "連載"),
                FilterOption(id: "complete", label: "完結"),
            ]),
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "all", label: "全部"),
                FilterOption(id: "hot", label: "熱門"),
                FilterOption(id: "new", label: "最新"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let category = filters["category"] ?? "all"
        let status   = filters["status"]   ?? "all"
        let sort     = filters["sort"]     ?? "all"
        let (galleries, totalPages) = try await EightcomicService.shared.fetchList(
            page: page, search: search, category: category, status: status, sort: sort)
        return ListPage(galleries: galleries,
                        currentPage: page,
                        totalPages: totalPages,
                        totalResults: totalPages * 48,
                        nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await EightcomicService.shared.fetchChapters(mangaURL: gallery.galleryURL)
    }

    func fetchImageData(url: URL) async throws -> Data {
        try await EHentaiService.shared.fetchImageData(url: url, referer: "https://www.8comic.com/")
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        try await EightcomicService.shared.fetchChapterImages(chapterURL: url)
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        await EightcomicService.shared.fetchGalleryDetail(galleryURL: gallery.galleryURL)
    }
}
