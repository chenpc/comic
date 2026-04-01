import AppKit
import CryptoKit
import Foundation

actor ImageLoader {
    static let shared = ImageLoader()

    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init() {
        memoryCache.countLimit = 80
        memoryCache.totalCostLimit = 300 * 1024 * 1024 // 300 MB
    }

    /// 磁碟快取目錄：若已設定 Library 目錄則放在 {library}/.cache，否則用系統 Caches
    private var diskCacheDir: URL {
        if let path = UserDefaults.standard.string(forKey: "comicLibraryPath"),
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).appendingPathComponent(".cache")
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.comic.imagecache")
    }

    // MARK: - Public

    /// 取得圖片（優先記憶體 → 磁碟 → 網路）
    /// - Parameter sourceID: 來源 ID，決定 throttle / referer 策略
    func image(for url: URL, sourceID: SourceID = .ehentai) async -> NSImage? {
        let key = cacheKey(for: url)

        if let img = memoryCache.object(forKey: key as NSString) {
            return img
        }

        if let img = loadFromDisk(key: key) {
            memoryCache.setObject(img, forKey: key as NSString)
            return img
        }

        // 若已有進行中的請求，等待它完成
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            await self.download(url: url, key: key, sourceID: sourceID)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// 預先下載（不阻塞）
    func prefetch(url: URL, sourceID: SourceID = .ehentai) {
        let key = cacheKey(for: url)

        if memoryCache.object(forKey: key as NSString) != nil { return }
        if diskFileExists(key: key) { return }
        if inFlight[key] != nil { return }

        let task = Task<NSImage?, Never> {
            await self.download(url: url, key: key, sourceID: sourceID)
        }
        inFlight[key] = task

        Task {
            _ = await task.value
            inFlight[key] = nil
        }
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// 確認所有 URL 的圖片都已在磁碟快取
    func allDiskCached(urls: [URL]) -> Bool {
        urls.allSatisfy { diskFileExists(key: cacheKey(for: $0)) }
    }

    /// 從磁碟快取讀取原始 data（供 auto-CBZ 打包使用）
    func readFromDisk(url: URL) -> Data? {
        try? Data(contentsOf: diskPath(key: cacheKey(for: url)))
    }

    /// 清除磁碟快取（同時清記憶體）
    func clearDiskCache() {
        memoryCache.removeAllObjects()
        let dir = diskCacheDir
        try? FileManager.default.removeItem(at: dir)
    }

    /// 磁碟快取佔用大小（bytes）
    func diskCacheSize() -> Int {
        let dir = diskCacheDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + size
        }
    }

    // MARK: - Private

    private func download(url: URL, key: String, sourceID: SourceID = .ehentai) async -> NSImage? {
        do {
            let data = try await fetchData(url: url, sourceID: sourceID)
            let img: NSImage?
            if let i = NSImage(data: data) {
                img = i
            } else if let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                img = NSImage(cgImage: cgImg, size: .zero)
            } else {
                img = nil
            }
            guard let img else { return nil }
            memoryCache.setObject(img, forKey: key as NSString, cost: data.count)
            saveToDisk(data: data, key: key)
            return img
        } catch {
            return nil
        }
    }

    /// 各 source 的圖片下載實作（由 source 註冊，各自處理 throttle / retry / referer）
    static var fetchers: [SourceID: (URL) async throws -> Data] = [:]

    /// 註冊 source 的圖片下載方法（App 啟動時由各 source 呼叫）
    static func registerFetcher(for sourceID: SourceID, _ fetcher: @escaping (URL) async throws -> Data) {
        fetchers[sourceID] = fetcher
    }

    private func fetchData(url: URL, sourceID: SourceID) async throws -> Data {
        guard let fetcher = Self.fetchers[sourceID] else {
            // fallback
            return try await EHentaiService.shared.fetchImageData(url: url, referer: "https://e-hentai.org")
        }
        return try await fetcher(url)
    }

    func cacheKey(for url: URL) -> String {
        // 使用 SHA256 確保跨次執行的穩定鍵值，避免 hashValue 每次不同造成快取錯位
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "\(hex).\(ext)"
    }

    private func diskPath(key: String) -> URL {
        diskCacheDir.appendingPathComponent(key)  // diskCacheDir 是 computed，每次取最新路徑
    }

    private func diskFileExists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: diskPath(key: key).path)
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let path = diskPath(key: key)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return NSImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        let dir = diskCacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(key))
    }
}
