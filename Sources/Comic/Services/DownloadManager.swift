import AppKit
import Foundation

private let dlLogURL = URL(fileURLWithPath: "/tmp/comic_dl.log")
private func dlog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: dlLogURL.path),
           let fh = try? FileHandle(forWritingTo: dlLogURL) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else {
            try? data.write(to: dlLogURL)
        }
    }
}

// MARK: - 下載進度檔（持久化）

struct DownloadProgress: Codable {
    var galleryID: String
    var galleryTitle: String
    var galleryToken: String
    var pageURLs: [String]        // 所有圖片頁面 URL
    var completedIndices: Set<Int> // 已完成的 index（0-based）

    var total: Int { pageURLs.count }
    var completed: Int { completedIndices.count }
    var isFinished: Bool { completedIndices.count == pageURLs.count && !pageURLs.isEmpty }
}

// MARK: - DownloadManager

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    enum DownloadState: Equatable {
        case notDownloaded
        case queued
        case downloading(page: Int, total: Int)
        case packaging
        case completed
        case failed(String)

        var isActive: Bool {
            switch self { case .queued, .downloading, .packaging: return true; default: return false }
        }
        var progress: Double {
            switch self {
            case .downloading(let p, let t): return t > 0 ? Double(p) / Double(t) : 0
            case .packaging, .completed: return 1.0
            default: return 0
            }
        }
    }

    @Published var states: [String: DownloadState] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // 漫畫櫃章節下載狀態（key = chapter.url.absoluteString）
    @Published var chapterStates: [String: DownloadState] = [:]
    private var chapterDownloadTasks: [String: Task<Void, Never>] = [:]

    // 供下載佇列頁面使用：記錄任務的 chapter/gallery 資訊與入隊順序
    @Published private(set) var chapterMeta: [String: (chapter: Chapter, gallery: Gallery, order: Int)] = [:]
    @Published private(set) var galleryMeta: [String: (gallery: Gallery, order: Int)] = [:]
    private var enqueueCounter = 0

    // 所有來源一次只下載一集（避免並行請求過多）
    private let chapterSem = AsyncSemaphore(limit: 1)

    // MARK: - 路徑（依來源分資料夾）

    // 漫畫名稱資料夾：{library}/manhuagui/{safeTitle}/
    func comicFolder(for gallery: Gallery) -> URL? {
        guard let lib = SettingsStore.shared.libraryURL else { return nil }
        return lib
            .appendingPathComponent(gallery.source)
            .appendingPathComponent(safeFilename(gallery.title))
    }

    // 章節 CBZ：{library}/manhuagui/{safeTitle}/{safeChapterTitle}.cbz
    func chapterCBZURL(chapter: Chapter, gallery: Gallery) -> URL? {
        guard let folder = comicFolder(for: gallery) else { return nil }
        let url = folder.appendingPathComponent("\(safeFilename(chapter.title)).cbz")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isChapterDownloaded(chapter: Chapter, gallery: Gallery) -> Bool {
        chapterCBZURL(chapter: chapter, gallery: gallery) != nil
    }

    func chapterState(chapter: Chapter, gallery: Gallery) -> DownloadState {
        if isChapterDownloaded(chapter: chapter, gallery: gallery) { return .completed }
        return chapterStates[chapter.url.absoluteString] ?? .notDownloaded
    }

    /// 掃描已下載的章節 CBZ 數量
    func downloadedChapterCount(gallery: Gallery) -> Int {
        guard let folder = comicFolder(for: gallery),
              FileManager.default.fileExists(atPath: folder.path) else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "cbz" }.count
    }

    nonisolated func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }

    private func stagingDir(for gallery: Gallery) -> URL? {
        SettingsStore.shared.libraryURL?
            .appendingPathComponent(".staging")
            .appendingPathComponent(gallery.source)
            .appendingPathComponent(gallery.id)
    }

    private func progressFile(for gallery: Gallery) -> URL? {
        stagingDir(for: gallery)?.appendingPathComponent("progress.json")
    }

    nonisolated func imageFile(stagingDir: URL, index: Int, ext: String) -> URL {
        stagingDir.appendingPathComponent(String(format: "%04d.%@", index + 1, ext))
    }

    // MARK: - Public

    func state(for gallery: Gallery) -> DownloadState {
        if cbzURL(for: gallery) != nil { return .completed }
        // 章節型來源：有任何章節 CBZ 在磁碟 = 已下載（跨重啟也能正確顯示）
        if (gallery.sourceID == .manhuagui || gallery.sourceID == .manhuaren || gallery.sourceID == .eightcomic),
           downloadedChapterCount(gallery: gallery) > 0 { return .completed }
        // 有 staging 目錄 = 已下載一部分
        if let dir = stagingDir(for: gallery),
           FileManager.default.fileExists(atPath: dir.path) {
            if let progress = loadProgress(gallery: gallery) {
                return .downloading(page: progress.completed, total: progress.total)
            }
        }
        return states[gallery.id] ?? .notDownloaded
    }

    func isDownloaded(_ gallery: Gallery) -> Bool {
        if cbzURL(for: gallery) != nil { return true }
        if (gallery.sourceID == .manhuagui || gallery.sourceID == .manhuaren || gallery.sourceID == .eightcomic) {
            return downloadedChapterCount(gallery: gallery) > 0
        }
        return false
    }

    func cbzURL(for gallery: Gallery) -> URL? {
        guard let lib = SettingsStore.shared.libraryURL else { return nil }
        // 新路徑：{library}/{source}/{id}.cbz
        let newURL = lib.appendingPathComponent(gallery.source).appendingPathComponent("\(gallery.id).cbz")
        if FileManager.default.fileExists(atPath: newURL.path) { return newURL }
        // 舊路徑（向後相容）：{library}/{id}.cbz
        let legacyURL = lib.appendingPathComponent("\(gallery.id).cbz")
        return FileManager.default.fileExists(atPath: legacyURL.path) ? legacyURL : nil
    }

    /// 開始下載（自動判斷是新下載或繼續）
    func download(gallery: Gallery) {
        let current = state(for: gallery)
        dlog("download() called for \(gallery.id), state=\(current)")
        switch current {
        case .notDownloaded, .failed, .downloading: break  // 允許開始/繼續/重試
        default:
            dlog("  skipped: already in state \(current)")
            return
        }
        guard SettingsStore.shared.libraryURL != nil else {
            dlog("  skipped: no library URL"); return
        }

        states[gallery.id] = .queued
        enqueueCounter += 1
        galleryMeta[gallery.id] = (gallery: gallery, order: enqueueCounter)
        let task = Task { await performDownload(gallery: gallery) }
        downloadTasks[gallery.id] = task
    }

    func downloadAll(bookmarks: [Gallery]) {
        for gallery in bookmarks where !isDownloaded(gallery) {
            download(gallery: gallery)
        }
    }

    func cancelDownload(gallery: Gallery) {
        downloadTasks[gallery.id]?.cancel()
        downloadTasks[gallery.id] = nil
        states[gallery.id] = .notDownloaded
    }

    /// 刪除已下載的所有檔案（書籤移除時呼叫）
    func deleteDownload(gallery: Gallery) {
        // 取消進行中的下載
        cancelDownload(gallery: gallery)
        // E-Hentai：刪除 CBZ
        if let cbz = cbzURL(for: gallery) {
            try? FileManager.default.removeItem(at: cbz)
        }
        // 章節型來源：刪除整個漫畫資料夾（含所有章節 CBZ）
        let isChapterBased = gallery.sourceID == .manhuagui || gallery.sourceID == .manhuaren || gallery.sourceID == .eightcomic
        if isChapterBased, let folder = comicFolder(for: gallery) {
            try? FileManager.default.removeItem(at: folder)
        }
        // 清除 staging 殘留
        if let staging = stagingDir(for: gallery) {
            try? FileManager.default.removeItem(at: staging)
        }
        states[gallery.id] = .notDownloaded
    }

    // MARK: - 漫畫櫃章節下載

    func downloadChapter(chapter: Chapter, gallery: Gallery) {
        let key = chapter.url.absoluteString
        guard !isChapterDownloaded(chapter: chapter, gallery: gallery) else { return }
        let current = chapterStates[key] ?? .notDownloaded
        guard !current.isActive else { return }
        chapterStates[key] = .queued
        enqueueCounter += 1
        chapterMeta[key] = (chapter: chapter, gallery: gallery, order: enqueueCounter)
        let task = Task { await performChapterDownload(chapter: chapter, gallery: gallery) }
        chapterDownloadTasks[key] = task
    }

    /// 瀏覽完一章後，從磁碟快取打包 CBZ（不重新下載）
    func autoCacheToCBZ(chapter: Chapter, gallery: Gallery, imageURLs: [URL]) async {
        guard SettingsStore.shared.libraryURL != nil else {
            dlog("autoCacheToCBZ: skip – no libraryURL"); return
        }
        guard !imageURLs.isEmpty else {
            dlog("autoCacheToCBZ: skip – no imageURLs"); return
        }
        guard !isChapterDownloaded(chapter: chapter, gallery: gallery) else {
            dlog("autoCacheToCBZ: skip – already downloaded \(chapter.title)"); return
        }

        let key = chapter.url.absoluteString
        // 避免重複執行
        if let s = chapterStates[key], s.isActive || s == .completed || s == .packaging {
            dlog("autoCacheToCBZ: skip – state=\(s) \(chapter.title)"); return
        }

        // 確認所有圖片都已在磁碟快取
        let allCached = await ImageLoader.shared.allDiskCached(urls: imageURLs)
        guard allCached else {
            dlog("autoCacheToCBZ: skip \(chapter.title) – not all cached (\(imageURLs.count) pages)")
            return
        }

        dlog("autoCacheToCBZ: START \(chapter.title)")
        chapterStates[key] = .packaging

        do {
            guard let folder = comicFolder(for: gallery) else { throw DownloadError.noImages }
            let stagingDir = folder.appendingPathComponent(".staging_auto_\(chapter.id)")
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // 從磁碟快取逐張複製，保留原始格式
            for (i, url) in imageURLs.enumerated() {
                guard let data = await ImageLoader.shared.readFromDisk(url: url) else {
                    dlog("autoCacheToCBZ: missing disk cache at index \(i)")
                    try? FileManager.default.removeItem(at: stagingDir)
                    chapterStates[key] = .notDownloaded
                    return
                }
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                try data.write(to: imageFile(stagingDir: stagingDir, index: i, ext: ext))
            }

            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let cbzDest = folder.appendingPathComponent("\(safeFilename(chapter.title)).cbz")
            try await packageAsCBZ(sourceDir: stagingDir, destination: cbzDest)
            try? FileManager.default.removeItem(at: stagingDir)
            chapterStates[key] = .completed
            dlog("autoCacheToCBZ: COMPLETED \(chapter.title)")
        } catch {
            dlog("autoCacheToCBZ: FAILED \(error)")
            chapterStates[key] = .notDownloaded
        }
    }

    func cancelChapterDownload(chapter: Chapter) {
        let key = chapter.url.absoluteString
        chapterDownloadTasks[key]?.cancel()
        chapterDownloadTasks[key] = nil
        chapterStates[key] = .notDownloaded
    }

    func pauseChapterDownload(chapter: Chapter) {
        cancelChapterDownload(chapter: chapter)
    }

    func pauseAllChapterDownloads(chapters: [Chapter]) {
        for chapter in chapters {
            let key = chapter.url.absoluteString
            let state = chapterStates[key] ?? .notDownloaded
            if state.isActive { pauseChapterDownload(chapter: chapter) }
        }
    }

    /// App 啟動時呼叫，掃描未完成的下載並自動恢復
    func resumePendingDownloads(bookmarks: [Gallery]) {
        guard let lib = SettingsStore.shared.libraryURL else { return }
        let stagingRoot = lib.appendingPathComponent(".staging")
        guard let topEntries = try? FileManager.default.contentsOfDirectory(
            at: stagingRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        for entry in topEntries {
            // 新結構：.staging/{source}/{galleryID}/
            let subEntries = (try? FileManager.default.contentsOfDirectory(
                at: entry, includingPropertiesForKeys: nil)) ?? []
            let dirs = subEntries.isEmpty ? [entry] : subEntries  // 舊結構 fallback
            for dir in dirs {
                let gid = dir.lastPathComponent
                if let gallery = bookmarks.first(where: { $0.id == gid }) {
                    guard let progress = loadProgress(gallery: gallery) else { continue }
                    guard !progress.isFinished else { continue }
                    dlog("resuming \(gid) (\(progress.completed)/\(progress.total))")
                    states[gid] = .downloading(page: progress.completed, total: progress.total)
                    let task = Task { await performDownload(gallery: gallery) }
                    downloadTasks[gid] = task
                }
            }
        }
    }

    // MARK: - Progress Persistence

    private func loadProgress(gallery: Gallery) -> DownloadProgress? {
        guard let file = progressFile(for: gallery),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(DownloadProgress.self, from: data)
    }

    private func saveProgress(_ progress: DownloadProgress, gallery: Gallery) {
        guard let file = progressFile(for: gallery),
              let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Core Download

    private func performDownload(gallery: Gallery) async {
        // 章節型來源（漫畫人、漫畫櫃）：先取章節列表再逐章下載
        let isChapterBased = gallery.sourceID == .manhuagui || gallery.sourceID == .manhuaren || gallery.sourceID == .eightcomic
        if isChapterBased {
            await performChapterBasedDownload(gallery: gallery)
            return
        }

        // E-Hentai 單 CBZ 流程
        dlog("performDownload START \(gallery.id) '\(gallery.title)'")
        guard let libURL = SettingsStore.shared.libraryURL else { return }
        guard let stagingDir = stagingDir(for: gallery) else { return }

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            var progress = loadProgress(gallery: gallery) ?? {
                DownloadProgress(galleryID: gallery.id,
                                 galleryTitle: gallery.title,
                                 galleryToken: gallery.token,
                                 pageURLs: [],
                                 completedIndices: [])
            }()

            if progress.pageURLs.isEmpty {
                dlog("  fetching page URLs...")
                progress.pageURLs = try await EHentaiService.shared.fetchImagePageURLs(galleryURL: gallery.galleryURL)
                dlog("  got \(progress.pageURLs.count) pages")
                saveProgress(progress, gallery: gallery)
            }

            let total = progress.pageURLs.count
            guard total > 0 else { throw DownloadError.noImages }

            for (i, pageURL) in progress.pageURLs.enumerated() {
                if Task.isCancelled { dlog("  CANCELLED at \(i+1)"); throw CancellationError() }
                if progress.completedIndices.contains(i) { continue }

                await MainActor.run {
                    states[gallery.id] = .downloading(page: progress.completed + 1, total: total)
                }
                if i % 10 == 0 { dlog("  page \(i+1)/\(total)") }

                var lastError: Error?
                for attempt in 1...3 {
                    do {
                        let imageURL = try await EHentaiService.shared.fetchImageURL(pageURL: pageURL)
                        let data = try await EHentaiService.shared.fetchImageData(url: imageURL)
                        let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
                        try data.write(to: imageFile(stagingDir: stagingDir, index: i, ext: ext))
                        progress.completedIndices.insert(i)
                        saveProgress(progress, gallery: gallery)
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        dlog("  page \(i+1) attempt \(attempt) failed: \(error.localizedDescription)")
                        if attempt < 3 {
                            try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                        }
                    }
                }
                if let err = lastError { throw err }
            }

            dlog("  packaging...")
            await MainActor.run { states[gallery.id] = .packaging }
            let sourceFolder = libURL.appendingPathComponent(gallery.source)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            let cbzDest = sourceFolder.appendingPathComponent("\(gallery.id).cbz")
            try await packageAsCBZ(sourceDir: stagingDir, destination: cbzDest)
            try? FileManager.default.removeItem(at: stagingDir)
            await MainActor.run { states[gallery.id] = .completed }
            dlog("  COMPLETED \(gallery.id)")

        } catch is CancellationError {
            dlog("  CANCELLED \(gallery.id) (progress saved)")
            await MainActor.run { states[gallery.id] = .notDownloaded }
        } catch {
            dlog("  FAILED \(gallery.id): \(error)")
            await MainActor.run { states[gallery.id] = .failed(error.localizedDescription) }
        }

        downloadTasks[gallery.id] = nil
    }

    /// 章節型來源整本下載：循序等待每集完成後再下載下一集
    private func performChapterBasedDownload(gallery: Gallery) async {
        dlog("performChapterBasedDownload START \(gallery.id)")
        do {
            let chapters: [Chapter]
            switch gallery.sourceID {
            case .manhuagui:  chapters = try await ManhuaguiService.shared.fetchChapters(comicURL: gallery.galleryURL)
            case .manhuaren:  chapters = try await ManhuarenService.shared.fetchChapters(galleryURL: gallery.galleryURL)
            case .eightcomic: chapters = try await EightcomicService.shared.fetchChapters(mangaURL: gallery.galleryURL)
            default: chapters = []
            }
            guard !chapters.isEmpty else {
                await MainActor.run { states[gallery.id] = .failed("無章節") }
                return
            }
            let total = chapters.count
            var done = 0
            await MainActor.run { states[gallery.id] = .downloading(page: 0, total: total) }
            for ch in chapters {
                if Task.isCancelled { break }
                if isChapterDownloaded(chapter: ch, gallery: gallery) { done += 1; continue }
                // 標記排隊中，循序等待此集完成再繼續
                await MainActor.run { chapterStates[ch.url.absoluteString] = .queued }
                await performChapterDownload(chapter: ch, gallery: gallery)
                done += 1
                await MainActor.run { states[gallery.id] = .downloading(page: done, total: total) }
            }
            await MainActor.run { states[gallery.id] = .completed }
        } catch is CancellationError {
            await MainActor.run { states[gallery.id] = .notDownloaded }
        } catch {
            dlog("  FAILED \(gallery.id): \(error)")
            await MainActor.run { states[gallery.id] = .failed(error.localizedDescription) }
        }
        downloadTasks[gallery.id] = nil
    }

    private nonisolated func performChapterDownload(chapter: Chapter, gallery: Gallery) async {
        let key = chapter.url.absoluteString

        // 所有來源：等待 semaphore，確保一次只下載一集
        await chapterSem.wait()
        defer { Task { await self.chapterSem.signal() } }
        dlog("performChapterDownload START \(chapter.id) '\(chapter.title)'")

        do {
            let imageURLs: [URL]
            switch gallery.sourceID {
            case .manhuagui:  imageURLs = try await ManhuaguiService.shared.fetchChapterImages(chapterURL: chapter.url)
            case .manhuaren:  imageURLs = try await ManhuarenService.shared.fetchChapterImages(chapterURL: chapter.url)
            case .eightcomic: imageURLs = try await EightcomicService.shared.fetchChapterImages(chapterURL: chapter.url)
            default: throw DownloadError.noImages
            }
            let total = imageURLs.count
            guard total > 0 else { throw DownloadError.noImages }

            let folder = await MainActor.run { comicFolder(for: gallery) }
            guard let folder else { throw DownloadError.noImages }
            let safe = safeFilename(chapter.title)
            let stagingDir = folder.appendingPathComponent(".staging_\(chapter.id)")
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            let fetcher = ImageLoader.fetchers[gallery.sourceID]
            for (i, imageURL) in imageURLs.enumerated() {
                if Task.isCancelled { throw CancellationError() }
                await MainActor.run { self.chapterStates[key] = .downloading(page: i + 1, total: total) }

                let data: Data
                if let fetcher {
                    data = try await fetcher(imageURL)
                } else {
                    data = try await EHentaiService.shared.fetchImageData(url: imageURL)
                }
                let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
                try data.write(to: imageFile(stagingDir: stagingDir, index: i, ext: ext))
            }

            await MainActor.run { self.chapterStates[key] = .packaging }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let cbzDest = folder.appendingPathComponent("\(safe).cbz")
            try await packageAsCBZ(sourceDir: stagingDir, destination: cbzDest)
            try? FileManager.default.removeItem(at: stagingDir)
            await MainActor.run { self.chapterStates[key] = .completed }
            dlog("  COMPLETED chapter \(chapter.id)")

        } catch is CancellationError {
            await MainActor.run { self.chapterStates[key] = .notDownloaded }
        } catch {
            dlog("  FAILED chapter \(chapter.id): \(error)")
            await MainActor.run { self.chapterStates[key] = .failed(error.localizedDescription) }
        }
        await MainActor.run { self.chapterDownloadTasks[key] = nil }
    }

    private nonisolated func packageAsCBZ(sourceDir: URL, destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", "-r", destination.path, sourceDir.path + "/"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                if p.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: DownloadError.zipFailed) }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Local Reading

    /// 直接從 CBZ 路徑解壓（Library 模式用）
    func extractedImageURLs(fromCBZ cbz: URL) async throws -> [URL] {
        let safeID = cbz.deletingPathExtension().lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comic_lib_\(safeID)")
        if FileManager.default.fileExists(atPath: tempDir.path) {
            return sortedImageURLs(in: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return try await unzipImages(cbz: cbz, to: tempDir)
    }

    func extractedImageURLs(for chapter: Chapter, gallery: Gallery) async throws -> [URL] {
        guard let cbz = chapterCBZURL(chapter: chapter, gallery: gallery) else {
            throw DownloadError.notDownloaded
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comic_ch_\(chapter.id)")
        if FileManager.default.fileExists(atPath: tempDir.path) {
            return sortedImageURLs(in: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return try await unzipImages(cbz: cbz, to: tempDir)
    }

    func extractedImageURLs(for gallery: Gallery) async throws -> [URL] {
        guard let cbz = cbzURL(for: gallery) else { throw DownloadError.notDownloaded }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comic_read_\(gallery.id)")
        if FileManager.default.fileExists(atPath: tempDir.path) {
            return sortedImageURLs(in: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return try await unzipImages(cbz: cbz, to: tempDir)
    }

    private func unzipImages(cbz: URL, to tempDir: URL) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", cbz.path, "-d", tempDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    let exts = Set(["jpg", "jpeg", "png", "webp", "gif"])
                    let urls = ((try? FileManager.default.contentsOfDirectory(
                        at: tempDir, includingPropertiesForKeys: nil)) ?? [])
                        .filter { exts.contains($0.pathExtension.lowercased()) }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    continuation.resume(returning: urls)
                } else {
                    continuation.resume(throwing: DownloadError.unzipFailed)
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func sortedImageURLs(in dir: URL) -> [URL] {
        let exts = Set(["jpg", "jpeg", "png", "webp", "gif"])
        return ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    enum DownloadError: LocalizedError {
        case noImages, zipFailed, unzipFailed, notDownloaded
        var errorDescription: String? {
            switch self {
            case .noImages:      return "找不到圖片"
            case .zipFailed:     return "壓縮失敗"
            case .unzipFailed:   return "解壓失敗"
            case .notDownloaded: return "尚未下載"
            }
        }
    }
}

// MARK: - AsyncSemaphore

/// 簡易 async semaphore（用於限制並行下載數量）
actor AsyncSemaphore {
    private let limit: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.count = limit
    }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}
