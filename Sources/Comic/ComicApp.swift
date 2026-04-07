import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // 視窗預設填滿螢幕（fit window size）
        if let window = NSApplication.shared.windows.first, let screen = window.screen {
            window.setFrame(screen.visibleFrame, display: true)
        }
        // SMB 自動 mount（若 library 路徑不存在且設定了 SMB URL）
        Task { @MainActor in
            await SettingsStore.shared.mountSMBIfNeeded()
        }
        // 恢復未完成的下載
        Task { @MainActor in
            let bookmarks = BookmarkStore.shared.bookmarks
            DownloadManager.shared.resumePendingDownloads(bookmarks: bookmarks)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ComicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 各 source 註冊圖片下載方法（含各自的 throttle / retry / referer）
        for source in [EHentaiSource.shared, ManhuaguiSource.shared,
                       ManhuarenSource.shared, EightcomicSource.shared,
                       MangaDexSource.shared, BaozimhSource.shared] as [ComicSource] {
            let s = source
            ImageLoader.registerFetcher(for: s.sourceID) { url in
                try await s.fetchImageData(url: url)
            }
            DownloadManager.register(s.sourceID, handlers: .init(
                hasChapters: s.hasChapters,
                fetchChapters: { gallery in try await s.fetchChapters(gallery: gallery) },
                fetchImageURLs: { url in try await s.fetchImageURLs(url: url) }
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
