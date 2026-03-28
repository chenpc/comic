import Foundation
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let ud = UserDefaults.standard

    @Published var libraryURL: URL? {
        didSet { ud.set(libraryURL?.path, forKey: "comicLibraryPath") }
    }

    @Published var prefetchCount: Int {
        didSet { ud.set(prefetchCount, forKey: "comicPrefetchCount") }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet { ud.set(iCloudSyncEnabled, forKey: "comicICloudSyncEnabled") }
    }

    init() {
        if let path = ud.string(forKey: "comicLibraryPath"),
           FileManager.default.fileExists(atPath: path) {
            libraryURL = URL(fileURLWithPath: path)
        }
        let saved = ud.integer(forKey: "comicPrefetchCount")
        prefetchCount = saved > 0 ? saved : 6
        if ud.object(forKey: "comicICloudSyncEnabled") == nil {
            iCloudSyncEnabled = true
        } else {
            iCloudSyncEnabled = ud.bool(forKey: "comicICloudSyncEnabled")
        }
    }

    func pickLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "選擇 Comic Library 資料夾"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.libraryURL = url }
        }
    }
}
