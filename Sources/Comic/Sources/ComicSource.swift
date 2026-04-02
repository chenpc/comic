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
    /// 新開來源時套用的預設篩選值（未設定的 key 視為「全部」）
    var defaultFilters: [String: String] { get }

    func fetchList(page: Int, search: String, filters: [String: String], extra: [String: Any]) async throws -> ListPage
    func fetchChapters(gallery: Gallery) async throws -> [Chapter]
    func fetchImageURLs(url: URL) async throws -> [URL]
    /// 下載圖片 data（各 source 自行處理 throttle / retry / referer）
    func fetchImageData(url: URL) async throws -> Data
    /// 漫畫詳細資料（作者、簡介）；不支援的 source 回傳 nil
    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail?
}

extension ComicSource {
    var defaultFilters: [String: String] { [:] }
    func fetchGalleryDetail(gallery: Gallery) async -> GalleryDetail? { return nil }
}

// MARK: - SourceManager

@MainActor
final class SourceManager: ObservableObject {
    static let shared = SourceManager()

    @Published var activeSourceID: SourceID {
        didSet { UserDefaults.standard.set(activeSourceID.rawValue, forKey: "activeSource") }
    }

    var activeSource: ComicSource { source(for: activeSourceID) }

    func source(for id: SourceID) -> ComicSource {
        switch id {
        case .ehentai:    return EHentaiSource.shared
        case .manhuagui:  return ManhuaguiSource.shared
        case .manhuaren:  return ManhuarenSource.shared
        case .eightcomic: return EightcomicSource.shared
        case .mangadex:   return MangaDexSource.shared
        case .baozimh:    return BaozimhSource.shared
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "activeSource") ?? ""
        activeSourceID = SourceID(rawValue: saved) ?? .ehentai
    }
}
