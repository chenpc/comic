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
            FilterGroup(id: "genre", label: "分類", options: [
                FilterOption(id: "", label: "全部"),
                // genre
                FilterOption(id: "391b0423-d847-456f-aff0-8b0cfc03066b", label: "動作"),
                FilterOption(id: "87cc87cd-a395-47af-b27a-93258283bbc6", label: "冒險"),
                FilterOption(id: "4d32cc48-9f00-4cca-9b5a-a839f0764984", label: "喜劇"),
                FilterOption(id: "b9af3a63-f058-46de-a9a0-e0c13906197a", label: "劇情"),
                FilterOption(id: "cdc58593-87dd-415e-bbc0-2ec27bf404cc", label: "奇幻"),
                FilterOption(id: "423e2eae-a7a2-4a8b-ac03-a8351462d71d", label: "愛情"),
                FilterOption(id: "ee968100-4191-4968-93d3-f82d72be7e46", label: "推理"),
                FilterOption(id: "cdad7e68-1419-41dd-bdce-27753074a640", label: "恐怖"),
                FilterOption(id: "33771934-028e-4cb3-8744-691e866a923e", label: "歷史"),
                FilterOption(id: "256c8bd9-4904-4360-bf4f-508a76d67183", label: "科幻"),
                FilterOption(id: "e5301a23-ebd9-49dd-a0cb-2add944c7fe9", label: "日常"),
                FilterOption(id: "3b60b75c-a2d7-4860-ab56-05f391bb889c", label: "心理"),
                FilterOption(id: "07251805-a27e-4d59-b488-f0bfbec15168", label: "驚悚"),
                FilterOption(id: "f8f62932-27da-4fe4-8ee1-6779a8c5edba", label: "悲劇"),
                FilterOption(id: "69964a64-2f90-4d33-beeb-f3ed2875eb4c", label: "運動"),
                FilterOption(id: "5920b825-4181-4a17-beeb-9918b0ff7a30", label: "耽美"),
                FilterOption(id: "a3c67850-4684-404e-9b7f-c69850ee5da6", label: "百合"),
                FilterOption(id: "ace04997-f6bd-436e-b261-779182193d3d", label: "異世界"),
                FilterOption(id: "acc803a4-c95a-4c22-86fc-eb6b582d82a2", label: "武俠"),
                // theme
                FilterOption(id: "eabc5b4c-6aff-42f3-b657-3e90cbd00b75", label: "超自然"),
                FilterOption(id: "caaa44eb-cd40-4177-b930-79d3ef2afe87", label: "校園"),
                FilterOption(id: "0bc90acb-ccc1-44ca-a34a-b9f3a73259d0", label: "轉生"),
                FilterOption(id: "aafb99c1-7f60-43fa-b75f-fc9502ce29c7", label: "後宮"),
                FilterOption(id: "5fff9cde-849c-4d78-aab0-0d52b2ee1d25", label: "求生"),
                FilterOption(id: "a1f53773-c69a-4ce5-8cab-fffcd90b1565", label: "魔法"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        let sort    = filters["sort"]  ?? "-updatedAt"
        let tagUUID = filters["genre"] ?? ""
        let (galleries, total) = try await MangaDexService.shared.fetchMangaList(
            page: page, search: search, orderBy: sort, tagUUID: tagUUID)
        let limit = 20
        let totalPages = max(1, Int(ceil(Double(total) / Double(limit))))
        return ListPage(galleries: galleries, currentPage: page, totalPages: totalPages,
                        totalResults: total, nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await MangaDexService.shared.fetchChapters(mangaID: gallery.id)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
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
