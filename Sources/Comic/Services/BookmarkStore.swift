import Foundation
import os.log

@MainActor
final class BookmarkStore: ObservableObject {
    private let log = Logger(subsystem: "com.chenpc.comic", category: "BookmarkStore")
    static let shared = BookmarkStore()

    @Published private(set) var bookmarks: [Gallery] = []
    @Published private(set) var isUsingiCloud = false
    @Published private(set) var cloudResolutionAttempted = false

    private var saveURL: URL
    private var cloudURL: URL?

    init() {
        saveURL = CloudStorageHelper.localDirectory.appendingPathComponent("bookmarks.json")
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
        let localURL = CloudStorageHelper.localDirectory.appendingPathComponent("bookmarks.json")
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
            let url = dir.appendingPathComponent("bookmarks.json")
            self.cloudURL = url
            CloudStorageHelper.migrateIfNeeded(from: self.saveURL, to: url)
            self.saveURL = url
            self.isUsingiCloud = true
            self.load()
            self.log.info("activateICloud: 完成，saveURL=\(url.path), isUsingiCloud=\(self.isUsingiCloud)")
        }
    }

    // MARK: - Public

    func isBookmarked(_ gallery: Gallery) -> Bool {
        bookmarks.contains { $0.id == gallery.id }
    }

    func toggle(_ gallery: Gallery) {
        if isBookmarked(gallery) {
            bookmarks.removeAll { $0.id == gallery.id }
            DownloadManager.shared.deleteDownload(gallery: gallery)
            ReadingProgressStore.shared.clear(galleryID: gallery.id)
        } else {
            bookmarks.insert(gallery, at: 0)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Gallery].self, from: data) else { return }
        bookmarks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}
