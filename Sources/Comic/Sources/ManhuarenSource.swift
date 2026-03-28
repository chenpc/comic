import Foundation

final class ManhuarenSource: ComicSource {
    static let shared = ManhuarenSource()

    let sourceID: SourceID = .manhuaren
    let supportsSearch     = true
    let hasChapters        = true

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "genre", label: "類型", options: [
                FilterOption(id: "",                    label: "全部"),
                FilterOption(id: "manhua-rexue",        label: "熱血"),
                FilterOption(id: "manhua-aiqing",       label: "愛情"),
                FilterOption(id: "manhua-xiaoyuan",     label: "校園"),
                FilterOption(id: "manhua-maoxian",      label: "冒險"),
                FilterOption(id: "manhua-gaoxiao",      label: "搞笑"),
                FilterOption(id: "manhua-mengxi",       label: "萌系"),
                FilterOption(id: "manhua-kehuan",       label: "科幻"),
                FilterOption(id: "manhua-mofa",         label: "魔法"),
                FilterOption(id: "manhua-xuanyi",       label: "懸疑"),
                FilterOption(id: "manhua-zhentan",      label: "偵探"),
                FilterOption(id: "manhua-kongbu",       label: "恐怖"),
                FilterOption(id: "manhua-zhiyu",        label: "治癒"),
                FilterOption(id: "manhua-meishi",       label: "美食"),
                FilterOption(id: "manhua-lishi",        label: "歷史"),
                FilterOption(id: "manhua-zhanzheng",    label: "戰爭"),
                FilterOption(id: "manhua-jingji",       label: "競技"),
                FilterOption(id: "manhua-zhichang",     label: "職場"),
                FilterOption(id: "manhua-lizhi",        label: "勵志"),
                FilterOption(id: "manhua-hougong",      label: "後宮"),
                FilterOption(id: "manhua-weiniang",     label: "偽娘"),
                FilterOption(id: "manhua-qihuan",       label: "奇幻"),
                FilterOption(id: "manhua-jizhan",       label: "機戰"),
                FilterOption(id: "manhua-dongfangshengui", label: "神鬼"),
                FilterOption(id: "manhua-tongren",      label: "同人"),
            ]),
            FilterGroup(id: "status", label: "進度", options: [
                FilterOption(id: "",                    label: "全部"),
                FilterOption(id: "manhua-completed",    label: "已完結"),
                FilterOption(id: "manhua-jpkr",         label: "日漫"),
                FilterOption(id: "manhua-original",     label: "原創"),
            ]),
        ]
    }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        // 優先用 status（有具體分類 slug），否則用 genre
        let slug = filters["status"].flatMap { $0.isEmpty ? nil : $0 }
                ?? filters["genre"].flatMap { $0.isEmpty ? nil : $0 }
                ?? ""
        let (galleries, totalPages) = try await ManhuarenService.shared.fetchComicList(
            page: page, search: search, slug: slug)
        return ListPage(galleries: galleries,
                        currentPage: page,
                        totalPages: totalPages,
                        totalResults: totalPages * 21,
                        nextCursor: nil)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await ManhuarenService.shared.fetchChapters(galleryURL: gallery.galleryURL)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        try await ManhuarenService.shared.fetchChapterImages(chapterURL: url)
    }
}
