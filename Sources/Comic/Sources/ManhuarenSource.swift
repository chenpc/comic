import Foundation

final class ManhuarenSource: ComicSource {
    static let shared = ManhuarenSource()

    let sourceID: SourceID = .manhuaren
    let supportsSearch     = true
    let hasChapters        = true
    let defaultFilters: [String: String] = ["sort": "2"]

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "",    label: "最熱門"),
                FilterOption(id: "2",   label: "最近更新"),
                FilterOption(id: "18",  label: "最新上架"),
            ]),
            FilterGroup(id: "area", label: "地區", options: [
                FilterOption(id: "",              label: "全部"),
                FilterOption(id: "manhua-jpkr",   label: "日漫/韓漫"),
            ]),
            FilterGroup(id: "genre", label: "類型", options: [
                FilterOption(id: "",                          label: "全部"),
                FilterOption(id: "manhua-rexue",              label: "熱血"),
                FilterOption(id: "manhua-aiqing",             label: "愛情"),
                FilterOption(id: "manhua-xiaoyuan",           label: "校園"),
                FilterOption(id: "manhua-maoxian",            label: "冒險"),
                FilterOption(id: "manhua-gaoxiao",            label: "搞笑"),
                FilterOption(id: "manhua-mengxi",             label: "萌系"),
                FilterOption(id: "manhua-kehuan",             label: "科幻"),
                FilterOption(id: "manhua-mofa",               label: "魔法"),
                FilterOption(id: "manhua-xuanyi",             label: "懸疑"),
                FilterOption(id: "manhua-zhentan",            label: "偵探"),
                FilterOption(id: "manhua-kongbu",             label: "恐怖"),
                FilterOption(id: "manhua-zhiyu",              label: "治癒"),
                FilterOption(id: "manhua-meishi",             label: "美食"),
                FilterOption(id: "manhua-lishi",              label: "歷史"),
                FilterOption(id: "manhua-zhanzheng",          label: "戰爭"),
                FilterOption(id: "manhua-jingji",             label: "競技/運動"),
                FilterOption(id: "manhua-zhichang",           label: "職場"),
                FilterOption(id: "manhua-lizhi",              label: "勵志"),
                FilterOption(id: "manhua-hougong",            label: "後宮"),
                FilterOption(id: "manhua-weiniang",           label: "偽娘"),
                FilterOption(id: "manhua-qihuan",             label: "奇幻"),
                FilterOption(id: "manhua-jizhan",             label: "機戰"),
                FilterOption(id: "manhua-dongfangshengui",    label: "神鬼"),
                FilterOption(id: "manhua-tongren",            label: "同人"),
                FilterOption(id: "manhua-shenghuoqinqing",    label: "生活"),
                FilterOption(id: "manhua-qingxiaoshuo1",      label: "輕小說改編"),
                FilterOption(id: "manhua-caihong",            label: "彩虹"),
                FilterOption(id: "manhua-jiecao",             label: "紳士"),
                FilterOption(id: "manhua-18-x",               label: "限制級"),
                FilterOption(id: "manhua-zheng18",            label: "限制精品"),
            ]),
            FilterGroup(id: "status", label: "進度", options: [
                FilterOption(id: "",                     label: "全部"),
                FilterOption(id: "manhua-list-st1",      label: "連載中"),
                FilterOption(id: "manhua-list-st2",      label: "已完結"),
                FilterOption(id: "manhua-original",      label: "原創"),
            ]),
        ]
    }

    // slug → AJAX param (key, value) 對應表
    private static let slugToParam: [String: (String, String)] = [
        // 地區
        "manhua-jpkr":             ("areaid",      "36"),
        // 類型
        "manhua-rexue":            ("tagid",       "31"),
        "manhua-aiqing":           ("tagid",       "26"),
        "manhua-xiaoyuan":         ("tagid",       "1"),
        "manhua-maoxian":          ("tagid",       "2"),
        "manhua-gaoxiao":          ("tagid",       "37"),
        "manhua-mengxi":           ("tagid",       "21"),
        "manhua-kehuan":           ("tagid",       "25"),
        "manhua-mofa":             ("tagid",       "15"),
        "manhua-xuanyi":           ("tagid",       "17"),
        "manhua-zhentan":          ("tagid",       "33"),
        "manhua-kongbu":           ("tagid",       "29"),
        "manhua-zhiyu":            ("tagid",       "9"),
        "manhua-meishi":           ("tagid",       "7"),
        "manhua-lishi":            ("tagid",       "4"),
        "manhua-zhanzheng":        ("tagid",       "12"),
        "manhua-jingji":           ("tagid",       "34"),
        "manhua-zhichang":         ("tagid",       "6"),
        "manhua-lizhi":            ("tagid",       "10"),
        "manhua-hougong":          ("tagid",       "8"),
        "manhua-weiniang":         ("tagid",       "5"),
        "manhua-qihuan":           ("tagid",       "14"),
        "manhua-jizhan":           ("tagid",       "40"),
        "manhua-dongfangshengui":  ("tagid",       "20"),
        "manhua-tongren":          ("tagid",       "30"),
        "manhua-shenghuoqinqing":  ("tagid",       "11"),
        "manhua-qingxiaoshuo1":    ("tagid",       "156"),
        "manhua-caihong":          ("tagid",       "27"),
        "manhua-jiecao":           ("tagid",       "36"),
        "manhua-18-x":             ("tagid",       "61"),
        "manhua-zheng18":          ("tagid",       "91"),
        // 進度
        "manhua-list-st1":         ("status",      "1"),
        "manhua-list-st2":         ("status",      "2"),
        "manhua-original":         ("iscopyright", "1"),
    ]

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        // 將所有篩選條件轉成 AJAX param overrides（支援多條件同時生效）
        var paramOverrides: [String: String] = [:]
        for key in ["area", "genre", "status"] {
            if let slug = filters[key], !slug.isEmpty,
               let (paramKey, paramVal) = Self.slugToParam[slug] {
                paramOverrides[paramKey] = paramVal
            }
        }
        if let sv = filters["sort"], !sv.isEmpty {
            paramOverrides["sort"] = sv
        }

        // 無任何篩選時用 slug URL（HTML 解析，效能較佳）
        // 有篩選時直接走 AJAX（ManhuarenService 內部處理）
        let slug = paramOverrides.isEmpty ? "" : ""

        let (galleries, totalPages) = try await ManhuarenService.shared.fetchComicList(
            page: page, search: search, slug: slug, paramOverrides: paramOverrides)
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

    func fetchImageData(url: URL) async throws -> Data {
        try await EHentaiService.shared.fetchImageData(url: url, referer: "https://www.manhuaren.com/")
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        await ManhuarenService.shared.fetchGalleryDetail(galleryURL: gallery.galleryURL)
    }
}
