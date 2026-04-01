import AppKit
import SwiftUI
import os.log

private let rlog = Logger(subsystem: "com.chenpc.comic", category: "AutoCBZ")

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var currentImage: NSImage?
    @Published var isLoading = false
    @Published var isLoadingGallery = false
    @Published var error: String?
    @Published var totalPages: Int = 0
    @Published var galleryTitle: String = ""
    @Published var jumpSheetVisible = false
    @Published var isLocalFile = false   // 是否讀取本地檔案

    private var imagePageURLs: [String] = []   // E-Hentai 頁面 URL
    private var localImageURLs: [URL] = []     // 本地 CBZ 模式
    private var directImageURLs: [URL] = []    // 漫畫櫃直接圖片 URL
    private var imageURLCache: [String: URL] = [:]
    private var loadTask: Task<Void, Never>?
    private var currentGallery: Gallery?
    private var prefetchCount: Int { SettingsStore.shared.prefetchCount }

    // 章節列表（漫畫櫃自動下一集用）
    private(set) var allChapters: [Chapter] = []
    private var currentChapterURL: URL?
    private var currentChapter: Chapter?

    // 自動打包：記錄已看過的頁面 index
    private var viewedPages: Set<Int> = []

    // MARK: - Gallery Loading

    func loadGallery(_ gallery: Gallery) async {
        currentGallery = gallery
        galleryTitle = gallery.title
        isLoadingGallery = true
        error = nil
        currentImage = nil
        totalPages = 0
        imagePageURLs = []
        localImageURLs = []
        directImageURLs = []
        imageURLCache = [:]
        viewedPages = []

        // 優先讀本地 CBZ
        if DownloadManager.shared.isDownloaded(gallery) {
            do {
                localImageURLs = try await DownloadManager.shared.extractedImageURLs(for: gallery)
                totalPages = localImageURLs.count
                isLocalFile = true
                isLoadingGallery = false
                if !localImageURLs.isEmpty { await navigate(to: 0) }
                return
            } catch {
                // 解壓失敗就 fallback 到網路
            }
        }

        // 網路讀取
        isLocalFile = false
        do {
            async let title = EHentaiService.shared.fetchGalleryTitle(galleryURL: gallery.galleryURL)
            async let pageURLs = EHentaiService.shared.fetchImagePageURLs(galleryURL: gallery.galleryURL)
            galleryTitle = try await title
            imagePageURLs = try await pageURLs
            totalPages = imagePageURLs.count
            isLoadingGallery = false
            if !imagePageURLs.isEmpty { await navigate(to: 0) }
        } catch {
            self.error = error.localizedDescription
            isLoadingGallery = false
        }
    }

    /// 直接載入圖片 URL 列表（漫畫櫃章節用）
    func loadChapter(_ chapter: Chapter, gallery: Gallery? = nil, allChapters: [Chapter] = [], startPage: Int = 0) async {
        galleryTitle = chapter.title
        currentChapterURL = chapter.url
        currentChapter = chapter
        if let gallery = gallery { currentGallery = gallery }
        if !allChapters.isEmpty { self.allChapters = allChapters }
        isLoadingGallery = true
        error = nil
        currentImage = nil
        totalPages = 0
        imagePageURLs = []
        localImageURLs = []
        directImageURLs = []
        imageURLCache = [:]
        viewedPages = []

        // Library 模式：chapter.url 直接是本地 CBZ 路徑
        if chapter.url.isFileURL && chapter.url.pathExtension.lowercased() == "cbz" {
            print("[Library] loadChapter local CBZ: \(chapter.url.path)")
            do {
                localImageURLs = try await DownloadManager.shared.extractedImageURLs(fromCBZ: chapter.url)
                totalPages = localImageURLs.count
                isLocalFile = true
                isLoadingGallery = false
                if !localImageURLs.isEmpty {
                    await navigate(to: min(startPage, totalPages - 1))
                }
                return
            } catch {
                self.error = error.localizedDescription
                isLoadingGallery = false
                return
            }
        }

        // 優先讀本地已下載的章節 CBZ
        if let gallery = currentGallery,
           DownloadManager.shared.isChapterDownloaded(chapter: chapter, gallery: gallery) {
            do {
                localImageURLs = try await DownloadManager.shared.extractedImageURLs(
                    for: chapter, gallery: gallery)
                totalPages = localImageURLs.count
                isLocalFile = true
                isLoadingGallery = false
                if !localImageURLs.isEmpty {
                    await navigate(to: min(startPage, totalPages - 1))
                }
                return
            } catch { }
        }

        isLocalFile = false
        do {
            let sourceID = currentGallery?.sourceID ?? .manhuagui
            let urls = try await SourceManager.shared.source(for: sourceID).fetchImageURLs(url: chapter.url)
            directImageURLs = urls
            totalPages = urls.count
            isLoadingGallery = false
            if !urls.isEmpty {
                await navigate(to: min(startPage, totalPages - 1))
            }
        } catch {
            self.error = error.localizedDescription
            isLoadingGallery = false
        }
    }

    // MARK: - Navigation

    func nextPage() {
        if currentIndex + 1 < totalPages {
            loadTask?.cancel()
            loadTask = Task { await navigate(to: currentIndex + 1) }
        } else if !directImageURLs.isEmpty || isLocalFile, let next = nextChapterInList() {
            // 已到最後一頁，自動載入下一集
            loadTask?.cancel()
            loadTask = Task { await loadChapter(next) }
        }
    }

    func prevPage() {
        if currentIndex > 0 {
            loadTask?.cancel()
            loadTask = Task { await navigate(to: currentIndex - 1) }
        } else if !directImageURLs.isEmpty || isLocalFile, let prev = prevChapterInList() {
            loadTask?.cancel()
            loadTask = Task { await loadChapter(prev) }
        }
    }

    func jumpTo(page: Int) {
        guard page >= 0 && page < totalPages else { return }
        loadTask?.cancel()
        loadTask = Task { await navigate(to: page) }
    }

    var hasNextChapter: Bool { nextChapterInList() != nil }
    var hasPrevChapter: Bool { prevChapterInList() != nil }

    func goToNextChapter() {
        guard let next = nextChapterInList() else { return }
        loadTask?.cancel()
        loadTask = Task { await loadChapter(next) }
    }

    func goToPrevChapter() {
        guard let prev = prevChapterInList() else { return }
        loadTask?.cancel()
        loadTask = Task { await loadChapter(prev) }
    }

    // MARK: - 自動下一集

    func nextChapterInList() -> Chapter? {
        guard !allChapters.isEmpty, let currentURL = currentChapterURL else { return nil }
        if currentGallery?.sourceID == .manhuagui {
            return ManhuaguiService.shared.findNextChapter(in: allChapters, currentURL: currentURL)
        }
        guard let idx = allChapters.firstIndex(where: { $0.url == currentURL }) else { return nil }
        let current = allChapters[idx]
        if let next = allChapters.adjacentChapter(after: current) { return next }
        // 回退：直接用 index + 1
        return idx + 1 < allChapters.count ? allChapters[idx + 1] : nil
    }

    func prevChapterInList() -> Chapter? {
        guard !allChapters.isEmpty, let currentURL = currentChapterURL else { return nil }
        if currentGallery?.sourceID == .manhuagui {
            return ManhuaguiService.shared.findPrevChapter(in: allChapters, currentURL: currentURL)
        }
        guard let idx = allChapters.firstIndex(where: { $0.url == currentURL }) else { return nil }
        let current = allChapters[idx]
        if let prev = allChapters.adjacentChapter(before: current) { return prev }
        return idx - 1 >= 0 ? allChapters[idx - 1] : nil
    }

    // MARK: - Private

    private func navigate(to index: Int) async {
        currentIndex = index
        isLoading = true
        error = nil
        // Snapshot arrays at the start to avoid race condition if loadChapter/loadGallery replaces them
        let snapshotLocal   = localImageURLs
        let snapshotDirect  = directImageURLs
        let snapshotPages   = imagePageURLs
        let localMode       = isLocalFile
        rlog.info("navigate idx=\(index)/\(self.totalPages) isLocal=\(localMode) directURLs=\(snapshotDirect.count) pageURLs=\(snapshotPages.count)")

        do {
            let img: NSImage?
            if localMode {
                guard index < snapshotLocal.count else { return }
                img = try await loadLocalImage(url: snapshotLocal[index])
            } else if !snapshotDirect.isEmpty {
                guard index < snapshotDirect.count else { return }
                img = await ImageLoader.shared.image(for: snapshotDirect[index], sourceID: currentGallery?.sourceID ?? .manhuagui)
            } else {
                guard index < snapshotPages.count else { return }
                let imageURL = try await resolveImageURL(pageURL: snapshotPages[index])
                img = await ImageLoader.shared.image(for: imageURL, sourceID: .ehentai)
            }

            guard currentIndex == index else { return }
            currentImage = img
            isLoading = false
            prefetchAhead(from: index)
            // 記錄頁數進度
            if let g = currentGallery, let ch = currentChapter {
                ReadingProgressStore.shared.record(gallery: g, chapter: ch, pageIndex: index)
            }
            // 到達最後一頁時嘗試觸發自動打包（prefetch 已提前快取後面的頁）
            if !isLocalFile, img != nil, !directImageURLs.isEmpty {
                viewedPages.insert(index)
                rlog.debug("viewedPages \(self.viewedPages.count)/\(self.totalPages) idx=\(index)")
                if index == totalPages - 1 {
                    rlog.info("reached last page, scheduling auto-CBZ check")
                    scheduleAutoCBZCheck()
                }
            }
        } catch {
            if currentIndex == index {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadLocalImage(url: URL) async throws -> NSImage? {
        return await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let img = NSImage(data: data) { return img }
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return NSImage(cgImage: cg, size: .zero)
            }
            return nil
        }.value
    }

    private func resolveImageURL(pageURL: String) async throws -> URL {
        if let cached = imageURLCache[pageURL] { return cached }
        let url = try await EHentaiService.shared.fetchImageURL(pageURL: pageURL)
        imageURLCache[pageURL] = url
        return url
    }

    /// 到達最後一頁後，等待 prefetch 完成，再確認全部快取後打包
    private func scheduleAutoCBZCheck() {
        guard let gallery = currentGallery else {
            rlog.error("scheduleAutoCBZCheck: no currentGallery"); return
        }
        guard let chapter = currentChapter else {
            rlog.error("scheduleAutoCBZCheck: no currentChapter"); return
        }
        guard BookmarkStore.shared.isBookmarked(gallery) else {
            rlog.error("scheduleAutoCBZCheck: skip – not bookmarked (\(gallery.title))"); return
        }
        rlog.error("scheduleAutoCBZCheck: \(chapter.title) urls=\(self.directImageURLs.count)")
        let urls = directImageURLs
        let ch = chapter
        let g = gallery
        Task {
            // 等待最多 30 秒讓 prefetch 完成
            for attempt in 1...6 {
                let allCached = await ImageLoader.shared.allDiskCached(urls: urls)
                rlog.info("scheduleAutoCBZCheck attempt \(attempt): allCached=\(allCached)")
                if allCached {
                    await DownloadManager.shared.autoCacheToCBZ(chapter: ch, gallery: g, imageURLs: urls)
                    return
                }
                // 等 5 秒後重試
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            rlog.warning("scheduleAutoCBZCheck: gave up waiting for full cache")
        }
    }

    private func prefetchAhead(from index: Int) {
        let count = prefetchCount
        if isLocalFile {
            let snapshotLocal = localImageURLs
            Task {
                let end = min(index + 1 + count, snapshotLocal.count)
                for i in (index + 1)..<end {
                    await ImageLoader.shared.prefetch(url: snapshotLocal[i])
                }
                // 若預讀超出章節末尾，繼續預讀下一集
                let remaining = count - (end - index - 1)
                if remaining > 0, let next = nextChapterInList() {
                    await prefetchNextChapter(next, count: remaining)
                }
            }
        } else if !directImageURLs.isEmpty {
            let snapshotDirect = directImageURLs
            let sid = currentGallery?.sourceID ?? .manhuagui
            Task {
                let end = min(index + 1 + count, snapshotDirect.count)
                for i in (index + 1)..<end {
                    await ImageLoader.shared.prefetch(url: snapshotDirect[i], sourceID: sid)
                }
                let remaining = count - (end - index - 1)
                if remaining > 0, let next = nextChapterInList() {
                    await prefetchNextChapter(next, count: remaining)
                }
            }
        } else {
            let snapshotPageURLs = imagePageURLs
            Task {
                let end = min(index + 1 + count, snapshotPageURLs.count)
                for i in (index + 1)..<end {
                    guard !Task.isCancelled else { break }
                    let pageURL = snapshotPageURLs[i]
                    if imageURLCache[pageURL] == nil,
                       let url = try? await EHentaiService.shared.fetchImageURL(pageURL: pageURL) {
                        imageURLCache[pageURL] = url
                        await ImageLoader.shared.prefetch(url: url, sourceID: .ehentai)
                    } else if let url = imageURLCache[pageURL] {
                        await ImageLoader.shared.prefetch(url: url, sourceID: .ehentai)
                    }
                }
                // E-Hentai 不跨章節預讀（無章節概念）
            }
        }
    }

    /// 預讀下一集的前 N 張圖
    private func prefetchNextChapter(_ chapter: Chapter, count: Int) async {
        let sid = currentGallery?.sourceID ?? .manhuagui
        guard let urls = try? await SourceManager.shared.source(for: sid).fetchImageURLs(url: chapter.url) else { return }
        for url in urls.prefix(count) {
            await ImageLoader.shared.prefetch(url: url, sourceID: sid)
        }
    }
}
