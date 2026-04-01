import Foundation
import AppKit
import NetFS
import os.log

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let ud = UserDefaults.standard
    private let log = Logger(subsystem: "com.chenpc.comic", category: "Settings")

    @Published var libraryURL: URL? {
        didSet { ud.set(libraryURL?.path, forKey: "comicLibraryPath") }
    }

    /// SMB 網路芳鄰 URL（例如 smb://NAS/comics）；非空時啟動自動 mount
    @Published var smbURL: String {
        didSet { ud.set(smbURL, forKey: "comicSMBURL") }
    }

    @Published var prefetchCount: Int {
        didSet { ud.set(prefetchCount, forKey: "comicPrefetchCount") }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet { ud.set(iCloudSyncEnabled, forKey: "comicICloudSyncEnabled") }
    }

    init() {
        smbURL = ud.string(forKey: "comicSMBURL") ?? ""
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
            Task { @MainActor in
                self?.libraryURL = url
                // 自動偵測 SMB（或其他網路掛載）並儲存 remount URL
                if let smb = Self.detectNetworkMountURL(for: url) {
                    self?.smbURL = smb
                    self?.log.info("auto-detected network mount: \(smb)")
                }
            }
        }
    }

    /// 若路徑所在的 volume 是網路掛載（SMB/AFP/NFS），回傳 remount URL 字串；否則回傳 nil
    static func detectNetworkMountURL(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeURLForRemountingKey]),
              let remount = values.volumeURLForRemounting else { return nil }
        let scheme = remount.scheme ?? ""
        guard ["smb", "afp", "nfs", "cifs"].contains(scheme) else { return nil }
        return remount.absoluteString
    }

    /// 啟動時：若 library 路徑不存在且儲存了網路掛載 URL，靜默 mount（不跳出帳號密碼對話框）
    func mountSMBIfNeeded() async {
        let smb = smbURL.trimmingCharacters(in: .whitespaces)
        guard !smb.isEmpty, let smbNetURL = URL(string: smb) else { return }

        // 若 library 路徑已存在，不需要 mount
        let savedPath = ud.string(forKey: "comicLibraryPath") ?? ""
        if FileManager.default.fileExists(atPath: savedPath) { return }

        log.info("SMB silent mount: \(smb)")
        await Self.netfsSilentMount(url: smbNetURL)

        // 等待 mount 完成（最多 15 秒，每秒輪詢）
        for attempt in 1...15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if FileManager.default.fileExists(atPath: savedPath) {
                log.info("SMB mount: ready after \(attempt)s")
                libraryURL = URL(fileURLWithPath: savedPath)
                return
            }
        }
        log.warning("SMB mount: path still not accessible after 15s")
    }

    /// 使用 NetFS 靜默掛載（kNAUIOptionNoUI = 不彈出帳密對話框）
    private static func netfsSilentMount(url: URL) async {
        await withCheckedContinuation { continuation in
            // kNAUIOptionNoUI：用 Keychain 憑證靜默掛載，無法取得密碼時直接失敗而非彈出對話框
            let openOptions = NSMutableDictionary()
            openOptions[kNAUIOptionKey] = kNAUIOptionNoUI

            var reqID: AsyncRequestID?
            let status = NetFSMountURLAsync(
                url as CFURL,
                nil,          // mountpath（nil = macOS 自動選 /Volumes/xxx）
                nil,          // user（從 Keychain 取）
                nil,          // password（從 Keychain 取）
                openOptions,
                nil,          // mount_options
                &reqID,
                DispatchQueue.global(),
                { _, _, _ in continuation.resume() }
            )
            if status != 0 {
                // 立即失敗（例如 URL 格式錯誤）
                continuation.resume()
            }
        }
    }
}
