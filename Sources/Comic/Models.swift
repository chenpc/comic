import Foundation

// MARK: - 來源

enum SourceID: String, CaseIterable, Identifiable, Codable {
    case ehentai   = "ehentai"
    case manhuagui = "manhuagui"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ehentai:   return "E-Hentai"
        case .manhuagui: return "漫畫櫃"
        }
    }

    var iconName: String {
        switch self {
        case .ehentai:   return "photo.on.rectangle.angled"
        case .manhuagui: return "book.closed"
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

// MARK: - Chapter（漫畫櫃章節）

struct Chapter: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let pageCount: Int?
}
