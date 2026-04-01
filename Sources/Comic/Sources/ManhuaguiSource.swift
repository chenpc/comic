import Foundation

final class ManhuaguiSource: ComicSource {
    static let shared = ManhuaguiSource()

    let sourceID: SourceID = .manhuagui
    let supportsSearch     = true
    let hasChapters        = true
    let defaultFilters: [String: String] = ["sort": "update"]

    // MARK: - 篩選群組定義（順序決定 URL 路徑順序）

    var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "area", label: "地區", options: [
                FilterOption(id: "",         label: "全部"),
                FilterOption(id: "japan",    label: "日本"),
                FilterOption(id: "hongkong", label: "港臺"),
                FilterOption(id: "other",    label: "其它"),
                FilterOption(id: "europe",   label: "歐美"),
                FilterOption(id: "china",    label: "內地"),
                FilterOption(id: "korea",    label: "韓國"),
            ]),
            FilterGroup(id: "genre", label: "劇情", options: [
                FilterOption(id: "",          label: "全部"),
                FilterOption(id: "rexue",     label: "熱血"),
                FilterOption(id: "maoxian",   label: "冒險"),
                FilterOption(id: "mohuan",    label: "魔幻"),
                FilterOption(id: "shengui",   label: "神鬼"),
                FilterOption(id: "gaoxiao",   label: "搞笑"),
                FilterOption(id: "mengxi",    label: "萌系"),
                FilterOption(id: "aiqing",    label: "愛情"),
                FilterOption(id: "kehuan",    label: "科幻"),
                FilterOption(id: "mofa",      label: "魔法"),
                FilterOption(id: "gedou",     label: "格鬥"),
                FilterOption(id: "wuxia",     label: "武俠"),
                FilterOption(id: "jizhan",    label: "機戰"),
                FilterOption(id: "zhanzheng", label: "戰爭"),
                FilterOption(id: "jingji",    label: "競技"),
                FilterOption(id: "tiyu",      label: "體育"),
                FilterOption(id: "xiaoyuan",  label: "校園"),
                FilterOption(id: "shenghuo",  label: "生活"),
                FilterOption(id: "lizhi",     label: "勵志"),
                FilterOption(id: "lishi",     label: "歷史"),
                FilterOption(id: "weiniang",  label: "偽娘"),
                FilterOption(id: "zhainan",   label: "宅男"),
                FilterOption(id: "funv",      label: "腐女"),
                FilterOption(id: "danmei",    label: "耽美"),
                FilterOption(id: "baihe",     label: "百合"),
                FilterOption(id: "hougong",   label: "後宮"),
                FilterOption(id: "zhiyu",     label: "治癒"),
                FilterOption(id: "meishi",    label: "美食"),
                FilterOption(id: "tuili",     label: "推理"),
                FilterOption(id: "xuanyi",    label: "懸疑"),
                FilterOption(id: "kongbu",    label: "恐怖"),
                FilterOption(id: "sige",      label: "四格"),
                FilterOption(id: "zhichang",  label: "職場"),
                FilterOption(id: "zhentan",   label: "偵探"),
                FilterOption(id: "shehui",    label: "社會"),
                FilterOption(id: "yinyue",    label: "音樂"),
                FilterOption(id: "wudao",     label: "舞蹈"),
                FilterOption(id: "zazhi",     label: "雜誌"),
                FilterOption(id: "heidao",    label: "黑道"),
            ]),
            FilterGroup(id: "audience", label: "受眾", options: [
                FilterOption(id: "",          label: "全部"),
                FilterOption(id: "shaonv",    label: "少女"),
                FilterOption(id: "shaonian",  label: "少年"),
                FilterOption(id: "qingnian",  label: "青年"),
                FilterOption(id: "ertong",    label: "兒童"),
                FilterOption(id: "tongyong",  label: "通用"),
            ]),
            FilterGroup(id: "year", label: "年份", options:
                [FilterOption(id: "", label: "全部")] +
                (["2026","2025","2024","2023","2022","2021","2020","2019","2018",
                  "2017","2016","2015","2014","2013","2012","2011","2010",
                  "200x","199x","198x","197x"])
                .map { FilterOption(id: $0, label: $0.hasSuffix("x") ? yearLabel($0) : "\($0)年") }
            ),
            FilterGroup(id: "letter", label: "字母", options:
                [FilterOption(id: "", label: "全部")] +
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { FilterOption(id: String($0).lowercased(), label: String($0)) } +
                [FilterOption(id: "0-9", label: "0-9")]
            ),
            FilterGroup(id: "status", label: "進度", options: [
                FilterOption(id: "",        label: "全部"),
                FilterOption(id: "lianzai", label: "連載"),
                FilterOption(id: "wanjie",  label: "完結"),
            ]),
            FilterGroup(id: "sort", label: "排序", options: [
                FilterOption(id: "",       label: "預設"),
                FilterOption(id: "update", label: "更新"),
                FilterOption(id: "view",   label: "人氣"),
                FilterOption(id: "score",  label: "評分"),
            ]),
        ]
    }

    private func yearLabel(_ id: String) -> String {
        switch id {
        case "200x": return "00年代"
        case "199x": return "90年代"
        case "198x": return "80年代"
        case "197x": return "更早"
        default: return id
        }
    }

    // MARK: - fetchList

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage {
        // 篩選 slug（排序除外）
        let filterOrder = ["area", "genre", "audience", "year", "letter", "status"]
        let filterSlugs = filterOrder.compactMap { gid -> String? in
            guard let v = filters[gid], !v.isEmpty else { return nil }
            return v
        }
        let sort = filters["sort"] ?? ""
        let (galleries, totalPages) = try await ManhuaguiService.shared.fetchComicList(
            page: page, search: search, filterSlugs: filterSlugs, sort: sort)
        return ListPage(galleries: galleries,
                        currentPage: page,
                        totalPages: totalPages,
                        totalResults: totalPages * 20,
                        nextCursor: nil)
    }

    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? {
        try? await ManhuaguiService.shared.fetchGalleryDetail(comicURL: gallery.galleryURL)
    }

    func fetchChapters(gallery: Gallery) async throws -> [Chapter] {
        try await ManhuaguiService.shared.fetchChapters(comicURL: gallery.galleryURL)
    }

    func fetchImageURLs(url: URL) async throws -> [URL] {
        try await ManhuaguiService.shared.fetchChapterImages(chapterURL: url)
    }

    func fetchImageData(url: URL) async throws -> Data {
        try await ManhuaguiThrottle.shared.fetchWithRetry {
            try await EHentaiService.shared.fetchImageData(url: url, referer: "https://tw.manhuagui.com")
        }
    }
}
