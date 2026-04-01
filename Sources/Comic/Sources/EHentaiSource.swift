import Foundation

final class EHentaiSource: ComicSource {
    static let shared = EHentaiSource()

    let sourceID: SourceID = .ehentai
    let supportsSearch     = true
    let hasChapters        = false

    var filterGroups: [FilterGroup] {
        let opts: [FilterOption] = [FilterOption(id: "", label: "全部")] +
            [EHCategory.doujinshi, .manga, .artistCG, .gameCG, .western,
             .nonH, .imageSet, .cosplay, .asianPorn, .misc]
            .map { FilterOption(id: "\($0.rawValue)", label: $0.displayName) }
        return [FilterGroup(id: "category", label: "分類", options: opts)]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let cursor = extra["cursor"] as? String
        var fCats = 0
        if let rawStr = filters["category"], let raw = Int(rawStr), raw > 0 {
            fCats = EHCategory.allMask & ~raw
        }
        let result = try await EHentaiService.shared.fetchGalleryList(
            next: cursor, search: search, fCats: fCats)
        let pageSize = 25
        let totalPages = result.totalResults > 0
            ? max(1, Int(ceil(Double(result.totalResults) / Double(pageSize))))
            : (result.nextCursor != nil ? page + 1 : page)
        return ListPage(galleries: result.galleries,
                        currentPage: page,
                        totalPages: totalPages,
                        totalResults: result.totalResults,
                        nextCursor: result.nextCursor)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] { [] }

    func fetchImageURLs(url: URL) async throws -> [URL] { [] }

    func fetchImageData(url: URL) async throws -> Data {
        try await EHentaiService.shared.fetchImageData(url: url, referer: "https://e-hentai.org")
    }
}
