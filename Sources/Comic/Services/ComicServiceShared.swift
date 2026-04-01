import Foundation

// MARK: - ComicService Protocol

/// 所有網站 Service 共同遵循的協定；提供 fetchHTML 的預設實作
protocol ComicService: AnyObject {
    /// 用於 HTTP 請求的 URLSession（各 service 可設不同 config）
    var session: URLSession { get }
    /// 發出請求時的 Referer header
    var referer: String { get }
    /// 速率限制器；nil 表示無需節流（預設 nil）
    var throttle: RequestThrottle? { get }
    /// 下載頁面 HTML；預設實作設定 User-Agent / Referer、檢查 2xx、UTF-8 解碼
    func fetchHTML(url: URL) async throws -> String
}

extension ComicService {
    var throttle: RequestThrottle? { nil }

    func fetchHTML(url: URL) async throws -> String {
        await throttle?.acquire()
        var request = URLRequest(url: url)
        request.setValue(ComicServiceConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ComicServiceError.badResponse
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

// MARK: - 共用常數

enum ComicServiceConstants {
    /// 完整 Safari/WebKit User-Agent（供多數網站使用）
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    /// 精簡版 User-Agent（漫畫櫃防爬蟲偵測用）
    static let userAgentShort = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
}

// MARK: - 共用錯誤型別

enum ComicServiceError: LocalizedError {
    case badResponse          // HTTP 非 2xx
    case invalidURL           // URL 格式錯誤
    case imageNotFound        // 圖片 URL 解析失敗
    case imageDataNotFound    // 圖片資料或 packer 解析失敗
    case parseError           // 頁面解析失敗

    var errorDescription: String? {
        switch self {
        case .badResponse:       return "伺服器回應錯誤"
        case .invalidURL:        return "無效的網址"
        case .imageNotFound:     return "找不到圖片"
        case .imageDataNotFound: return "找不到圖片資料"
        case .parseError:        return "解析頁面失敗"
        }
    }
}
