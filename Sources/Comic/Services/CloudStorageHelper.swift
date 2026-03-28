import Foundation
import os.log

/// 統一管理 iCloud / 本機儲存路徑
/// - iCloud Drive 可用時存到 ~/Library/Mobile Documents/com~apple~CloudDocs/Comic/
/// - 不可用時 fallback 到 Application Support/Comic
enum CloudStorageHelper {

    private static let log = Logger(subsystem: "com.chenpc.comic", category: "CloudStorage")

    /// 同步解析 iCloud Drive Documents 目錄（不需要 entitlement）
    /// - iCloud Drive 停用或目錄無法建立時回傳 nil
    static func resolveCloudDirectory(
        resolver: (() -> URL?)? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        Task.detached(priority: .utility) {
            let url: URL?
            if let resolver {
                url = resolver()
            } else {
                url = iCloudDriveDirectory()
            }
            if let url {
                log.info("resolveCloudDirectory: iCloud Drive 目錄就緒 → \(url.path)")
            } else {
                log.warning("resolveCloudDirectory: iCloud Drive 不可用")
            }
            await MainActor.run { completion(url) }
        }
    }

    /// iCloud Drive 的 Comic 子目錄
    /// ~/Library/Mobile Documents/com~apple~CloudDocs/Comic/
    static func iCloudDriveDirectory() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudDrive = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Mobile Documents")
            .appendingPathComponent("com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: iCloudDrive.path) else {
            log.warning("iCloudDriveDirectory: iCloud Drive 目錄不存在（未啟用？）")
            return nil
        }
        let dir = iCloudDrive.appendingPathComponent("Comic")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            log.error("iCloudDriveDirectory: 建立目錄失敗 — \(error.localizedDescription)")
            return nil
        }
    }

    /// 本機 fallback 目錄（Application Support/Comic）
    static var localDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Comic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 若 src 存在，將 src 搬移到 dst（覆蓋），回傳是否成功
    @discardableResult
    static func migrate(from src: URL, to dst: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: src.path) else {
            log.debug("migrate: src 不存在，略過 (\(src.lastPathComponent))")
            return false
        }
        do {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: src, to: dst)
            log.info("migrate: \(src.lastPathComponent) 搬移成功 → \(dst.path)")
            return true
        } catch {
            log.error("migrate: 搬移失敗 — \(error.localizedDescription)")
            return false
        }
    }

    /// 若 src 存在且 dst 不存在，才搬移（首次啟用 iCloud 時使用），回傳是否成功
    @discardableResult
    static func migrateIfNeeded(from src: URL, to dst: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: src.path) else {
            log.debug("migrateIfNeeded: src 不存在，略過 (\(src.lastPathComponent))")
            return false
        }
        guard !FileManager.default.fileExists(atPath: dst.path) else {
            log.debug("migrateIfNeeded: dst 已存在，略過 (\(dst.lastPathComponent))")
            return false
        }
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            log.info("migrateIfNeeded: \(src.lastPathComponent) 搬移成功 → \(dst.path)")
            return true
        } catch {
            log.error("migrateIfNeeded: 搬移失敗 — \(error.localizedDescription)")
            return false
        }
    }
}
