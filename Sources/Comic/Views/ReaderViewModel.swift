import AppKit
import SwiftUI

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

        do {
            let img: NSImage?
            if isLocalFile {
                img = try await loadLocalImage(at: index)
            } else if !directImageURLs.isEmpty {
                img = await ImageLoader.shared.image(for: directImageURLs[index], referer: imageReferer)
            } else {
                let imageURL = try await resolveImageURL(at: index)
                img = await ImageLoader.shared.image(for: imageURL)
            }

            guard currentIndex == index else { return }
            currentImage = img
            isLoading = false
            prefetchAhead(from: index)
            // 記錄頁數進度
            if let g = currentGallery, let ch = currentChapter {
                ReadingProgressStore.shared.record(gallery: g, chapter: ch, pageIndex: index)
            }
        } catch {
            if currentIndex == index {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadLocalImage(at index: Int) async throws -> NSImage? {
        let url = localImageURLs[index]
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

    private func resolveImageURL(at index: Int) async throws -> URL {
        let pageURL = imagePageURLs[index]
        if let cached = imageURLCache[pageURL] { return cached }
        let url = try await EHentaiService.shared.fetchImageURL(pageURL: pageURL)
        imageURLCache[pageURL] = url
        return url
    }

    private func prefetchAhead(from index: Int) {
        let count = prefetchCount
        if isLocalFile {
            Task {
                let end = min(index + 1 + count, localImageURLs.count)
                for i in (index + 1)..<end {
                    await ImageLoader.shared.prefetch(url: localImageURLs[i])
                }
                // 若預讀超出章節末尾，繼續預讀下一集
                let remaining = count - (end - index - 1)
                if remaining > 0, let next = nextChapterInList() {
                    await prefetchNextChapter(next, count: remaining)
                }
            }
        } else if !directImageURLs.isEmpty {
            let referer = imageReferer
            Task {
                let end = min(index + 1 + count, directImageURLs.count)
                for i in (index + 1)..<end {
                    await ImageLoader.shared.prefetch(url: directImageURLs[i], referer: referer)
                }
                let remaining = count - (end - index - 1)
                if remaining > 0, let next = nextChapterInList() {
                    await prefetchNextChapter(next, count: remaining)
                }
            }
        } else {
            Task {
                let end = min(index + 1 + count, imagePageURLs.count)
                for i in (index + 1)..<end {
                    guard !Task.isCancelled else { break }
                    let pageURL = imagePageURLs[i]
                    if imageURLCache[pageURL] == nil,
                       let url = try? await EHentaiService.shared.fetchImageURL(pageURL: pageURL) {
                        imageURLCache[pageURL] = url
                        await ImageLoader.shared.prefetch(url: url)
                    } else if let url = imageURLCache[pageURL] {
                        await ImageLoader.shared.prefetch(url: url)
                    }
                }
                // E-Hentai 不跨章節預讀（無章節概念）
            }
        }
    }

    /// 預讀下一集的前 N 張圖
    private func prefetchNextChapter(_ chapter: Chapter, count: Int) async {
        let sourceID = currentGallery?.sourceID ?? .manhuagui
        guard let urls = try? await SourceManager.shared.source(for: sourceID).fetchImageURLs(url: chapter.url) else { return }
        for url in urls.prefix(count) {
            await ImageLoader.shared.prefetch(url: url, referer: imageReferer)
        }
    }

    private var imageReferer: String {
        switch currentGallery?.sourceID {
        case .manhuaren:  return "https://www.manhuaren.com/"
        case .eightcomic: return "https://www.8comic.com/"
        default:          return "https://tw.manhuagui.com"
        }
    }
}
