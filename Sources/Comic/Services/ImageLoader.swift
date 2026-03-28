import AppKit
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
    /// - Parameter referer: 下載時使用的 Referer header（nil = 自動根據 host 選擇）
    func image(for url: URL, referer: String? = nil) async -> NSImage? {
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
            await self.download(url: url, key: key, referer: referer)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// 預先下載（不阻塞）
    func prefetch(url: URL, referer: String? = nil) {
        let key = cacheKey(for: url)

        if memoryCache.object(forKey: key as NSString) != nil { return }
        if diskFileExists(key: key) { return }
        if inFlight[key] != nil { return }

        let task = Task<NSImage?, Never> {
            await self.download(url: url, key: key, referer: referer)
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

    private func download(url: URL, key: String, referer: String? = nil) async -> NSImage? {
        do {
            let data = try await fetchData(url: url, referer: referer)
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

    /// 根據 URL host 選擇適當的 Referer 下載圖片
    private func fetchData(url: URL, referer: String?) async throws -> Data {
        let effectiveReferer: String
        if let referer {
            effectiveReferer = referer
        } else if let host = url.host, host.contains("hentai") || host.contains("ehgt") {
            effectiveReferer = "https://e-hentai.org"
        } else {
            effectiveReferer = "https://e-hentai.org"  // default
        }
        // 直接用 EHentaiService 的 session 發送（已有 UA 等 header）
        return try await EHentaiService.shared.fetchImageData(url: url, referer: effectiveReferer)
    }

    func cacheKey(for url: URL) -> String {
        // 使用 URL hash 避免檔名衝突
        let hash = abs(url.absoluteString.hashValue)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "\(hash).\(ext)"
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
