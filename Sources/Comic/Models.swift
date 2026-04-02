import Foundation

// MARK: - 來源

enum SourceID: String, CaseIterable, Identifiable, Codable {
    case ehentai    = "ehentai"
    case manhuagui  = "manhuagui"
    case manhuaren  = "manhuaren"
    case eightcomic = "8comic"
    case mangadex   = "mangadex"
    case baozimh    = "baozimh"
    case copymanga  = "copymanga"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ehentai:    return "E-Hentai"
        case .manhuagui:  return "漫畫櫃"
        case .manhuaren:  return "漫畫人"
        case .eightcomic: return "無限動漫"
        case .mangadex:   return "MangaDex"
        case .baozimh:    return "包子漫畫"
        case .copymanga:  return "拷貝漫畫"
        }
    }

    var iconName: String {
        switch self {
        case .ehentai:    return "photo.on.rectangle.angled"
        case .manhuagui:  return "book.closed"
        case .manhuaren:  return "books.vertical"
        case .eightcomic: return "infinity"
        case .mangadex:   return "globe"
        case .baozimh:    return "square.stack"
        case .copymanga:  return "doc.on.doc"
        }
    }
}

// MARK: - 分類（E-Hentai 專用）

enum EHCategory: Int, CaseIterable, Identifiable {
    case misc       = 1
    case doujinshi  = 2
    case manga      = 4
    case artistCG   = 8
    case gameCG     = 16
    case imageSet   = 32
    case cosplay    = 64
    case asianPorn  = 128
    case nonH       = 256
    case western    = 512

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .misc:      return "Misc"
        case .doujinshi: return "Doujinshi"
        case .manga:     return "Manga"
        case .artistCG:  return "Artist CG"
        case .gameCG:    return "Game CG"
        case .imageSet:  return "Image Set"
        case .cosplay:   return "Cosplay"
        case .asianPorn: return "Asian Porn"
        case .nonH:      return "Non-H"
        case .western:   return "Western"
        }
    }

    static let allMask: Int = EHCategory.allCases.reduce(0) { $0 | $1.rawValue }
}

// MARK: - Gallery

struct Gallery: Identifiable, Hashable, Codable {
    let id: String
    let token: String
    let title: String
    let thumbURL: URL?
    let pageCount: Int?
    let category: String?
    let uploader: String?
    let source: String      // "ehentai" or "manhuagui"
    let galleryURL: URL     // 儲存的 URL，不再計算

    // E-Hentai 用的便利 init（向後相容）
    init(id: String, token: String, title: String, thumbURL: URL?,
         pageCount: Int?, category: String?, uploader: String?) {
        self.id = id
        self.token = token
        self.title = title
        self.thumbURL = thumbURL
        self.pageCount = pageCount
        self.category = category
        self.uploader = uploader
        self.source = SourceID.ehentai.rawValue
        self.galleryURL = URL(string: "https://e-hentai.org/g/\(id)/\(token)/")!
    }

    // 完整 init
    init(id: String, token: String, title: String, thumbURL: URL?,
         pageCount: Int?, category: String?, uploader: String?,
         source: String, galleryURL: URL) {
        self.id = id; self.token = token; self.title = title
        self.thumbURL = thumbURL; self.pageCount = pageCount
        self.category = category; self.uploader = uploader
        self.source = source; self.galleryURL = galleryURL
    }

    // MARK: Codable（向後相容舊書籤，沒有 source/galleryURL 欄位）

    enum CodingKeys: String, CodingKey {
        case id, token, title, thumbURL, pageCount, category, uploader, source, galleryURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        token    = try c.decode(String.self, forKey: .token)
        title    = try c.decode(String.self, forKey: .title)
        thumbURL = try c.decodeIfPresent(URL.self, forKey: .thumbURL)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        uploader = try c.decodeIfPresent(String.self, forKey: .uploader)
        source   = try c.decodeIfPresent(String.self, forKey: .source) ?? SourceID.ehentai.rawValue
        if let url = try c.decodeIfPresent(URL.self, forKey: .galleryURL) {
            galleryURL = url
        } else {
            galleryURL = URL(string: "https://e-hentai.org/g/\(id)/\(token)/")!
        }
    }

    var sourceID: SourceID { SourceID(rawValue: source) ?? .ehentai }
}

// MARK: - GalleryDetail（漫畫詳細資料）

struct GalleryDetail {
    let author: String?
    let description: String?
    // 可選欄位：各 source 視可用資料填入
    let tags: [String]?         // 標籤列表
    let status: String?         // 連載狀態（連載中 / 完結 / 休刊）
    let updateDate: String?     // 最後更新日期

    init(author: String? = nil, description: String? = nil,
         tags: [String]? = nil, status: String? = nil, updateDate: String? = nil) {
        self.author      = author
        self.description = description
        self.tags        = tags
        self.status      = status
        self.updateDate  = updateDate
    }
}

// MARK: - Chapter（漫畫櫃章節）

struct Chapter: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let pageCount: Int?
}

// MARK: - Chapter 集數導航輔助

extension Chapter {
    /// 從標題擷取集數與後綴（集/回/卷/話/章/期），回傳 (number, suffix)
    var chapterNumber: (Double, String)? {
        guard let m = title.range(of: #"(\d+(?:\.\d+)?)\s*([集回卷話章期]?)"#,
                                  options: .regularExpression) else { return nil }
        let matched = title[m]
        guard let numRange = matched.range(of: #"^\d+(?:\.\d+)?"#, options: .regularExpression),
              let num = Double(matched[numRange]) else { return nil }
        let suffix = String(matched[numRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (num, suffix)
    }
}

extension [Chapter] {
    /// 找下一集：優先找數字剛好大一點的，同數字多個時優先後綴相同的
    func adjacentChapter(after current: Chapter) -> Chapter? {
        guard let (curNum, curSuffix) = current.chapterNumber else { return nil }
        let candidates = compactMap { ch -> (Double, String, Chapter)? in
            guard let (n, s) = ch.chapterNumber, n > curNum else { return nil }
            return (n, s, ch)
        }.sorted { $0.0 < $1.0 }
        guard !candidates.isEmpty else { return nil }
        let nextNum = candidates[0].0
        let sameNum = candidates.filter { $0.0 == nextNum }
        if sameNum.count == 1 { return sameNum[0].2 }
        return sameNum.first(where: { $0.1 == curSuffix })?.2 ?? sameNum[0].2
    }

    /// 找上一集：優先找數字剛好小一點的，同數字多個時優先後綴相同的
    func adjacentChapter(before current: Chapter) -> Chapter? {
        guard let (curNum, curSuffix) = current.chapterNumber else { return nil }
        let candidates = compactMap { ch -> (Double, String, Chapter)? in
            guard let (n, s) = ch.chapterNumber, n < curNum else { return nil }
            return (n, s, ch)
        }.sorted { $0.0 > $1.0 }
        guard !candidates.isEmpty else { return nil }
        let prevNum = candidates[0].0
        let sameNum = candidates.filter { $0.0 == prevNum }
        if sameNum.count == 1 { return sameNum[0].2 }
        return sameNum.first(where: { $0.1 == curSuffix })?.2 ?? sameNum[0].2
    }
}
