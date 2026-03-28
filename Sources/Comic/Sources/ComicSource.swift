import Foundation

// MARK: - 分頁結果

struct ListPage {
    let galleries: [Gallery]
    let currentPage: Int
    let totalPages: Int
    let totalResults: Int
    let nextCursor: String?   // E-Hentai 用
}

// MARK: - 彈性分類系統

struct FilterOption: Identifiable, Hashable {
    let id: String    // URL slug 或參數值；"" 代表「全部」
    let label: String
}

struct FilterGroup: Identifiable {
    let id: String    // 唯一鍵，用於 selectedFilters 字典
    let label: String // 顯示標籤，e.g. "地區"
    let options: [FilterOption]  // options[0] 永遠是「全部」(id: "")

    var allOption: FilterOption { options[0] }
}

// MARK: - ComicSource 協定

protocol ComicSource: AnyObject {
    var sourceID: SourceID { get }
    var supportsSearch: Bool { get }
    var hasChapters: Bool { get }
    /// 各來源自定義的篩選群組（空陣列代表不支援篩選）
    var filterGroups: [FilterGroup] { get }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage
    func fetchChapters(gallery: Gallery) async throws -> [Chapter]
    func fetchImageURLs(url: URL) async throws -> [URL]
}

// MARK: - SourceManager

@MainActor
final class SourceManager: ObservableObject {
    static let shared = SourceManager()

    @Published var activeSourceID: SourceID {
        didSet { UserDefaults.standard.set(activeSourceID.rawValue, forKey: "activeSource") }
    }

    var activeSource: ComicSource {
        switch activeSourceID {
        case .ehentai:   return EHentaiSource.shared
        case .manhuagui: return ManhuaguiSource.shared
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "activeSource") ?? ""
        activeSourceID = SourceID(rawValue: saved) ?? .ehentai
    }
}
