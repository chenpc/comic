import Foundation
import os.log

struct ReadingProgress: Codable {
    let galleryID: String
    let chapterID: String
    let chapterTitle: String
    let chapterURL: URL
    var pageIndex: Int          // 0-based
    let lastReadAt: Date

    init(galleryID: String, chapterID: String, chapterTitle: String,
         chapterURL: URL, pageIndex: Int, lastReadAt: Date) {
        self.galleryID    = galleryID
        self.chapterID    = chapterID
        self.chapterTitle = chapterTitle
        self.chapterURL   = chapterURL
        self.pageIndex    = pageIndex
        self.lastReadAt   = lastReadAt
    }

    // 向後相容：舊資料沒有 pageIndex 欄位時預設為 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        galleryID    = try c.decode(String.self, forKey: .galleryID)
        chapterID    = try c.decode(String.self, forKey: .chapterID)
        chapterTitle = try c.decode(String.self, forKey: .chapterTitle)
        chapterURL   = try c.decode(URL.self,    forKey: .chapterURL)
        pageIndex    = try c.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0
        lastReadAt   = try c.decode(Date.self,   forKey: .lastReadAt)
    }
}

@MainActor
final class ReadingProgressStore: ObservableObject {
    static let shared = ReadingProgressStore()

    @Published private(set) var progress: [String: ReadingProgress] = [:]
    @Published private(set) var isUsingiCloud = false
    @Published private(set) var cloudResolutionAttempted = false

    private let log = Logger(subsystem: "com.chenpc.comic", category: "ReadingProgressStore")
    private var saveURL: URL
    private var cloudURL: URL?

    init() {
        saveURL = CloudStorageHelper.localDirectory.appendingPathComponent("reading_progress.json")
        load()
        if SettingsStore.shared.iCloudSyncEnabled {
            activateICloud()
        }
    }

    // MARK: - iCloud 開關

    func enableICloud() {
        guard !isUsingiCloud else { return }
        activateICloud()
    }

    func disableICloud() {
        guard isUsingiCloud, let cloudURL else {
            cloudResolutionAttempted = false
            isUsingiCloud = false
            return
        }
        let localURL = CloudStorageHelper.localDirectory.appendingPathComponent("reading_progress.json")
        CloudStorageHelper.migrate(from: cloudURL, to: localURL)
        saveURL = localURL
        isUsingiCloud = false
        cloudResolutionAttempted = false
        self.cloudURL = nil
    }

    // MARK: - Private

    private func activateICloud() {
        log.info("activateICloud: 開始")
        CloudStorageHelper.resolveCloudDirectory { [self] dir in
            self.cloudResolutionAttempted = true
            guard let dir else {
                self.log.warning("activateICloud: iCloud 不可用，維持本機儲存")
                return
            }
            let url = dir.appendingPathComponent("reading_progress.json")
            self.cloudURL = url
            CloudStorageHelper.migrateIfNeeded(from: self.saveURL, to: url)
            self.saveURL = url
            self.isUsingiCloud = true
            self.load()
            self.log.info("activateICloud: 完成，saveURL=\(url.path), isUsingiCloud=\(self.isUsingiCloud)")
        }
    }

    // MARK: - Public

    func record(gallery: Gallery, chapter: Chapter, pageIndex: Int = 0) {
        progress[gallery.id] = ReadingProgress(
            galleryID: gallery.id,
            chapterID: chapter.id,
            chapterTitle: chapter.title,
            chapterURL: chapter.url,
            pageIndex: pageIndex,
            lastReadAt: Date()
        )
        save()
    }

    func lastRead(galleryID: String) -> ReadingProgress? {
        progress[galleryID]
    }

    func clear(galleryID: String) {
        progress.removeValue(forKey: galleryID)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([String: ReadingProgress].self, from: data)
        else { return }
        progress = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}
