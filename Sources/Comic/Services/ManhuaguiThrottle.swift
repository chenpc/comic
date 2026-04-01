import Foundation
import os.log

/// 通用速率限制器：每秒最多 `maxPerSecond` 次請求
/// 重試策略：最多 `maxRetries` 次，間隔 `retryDelay` 秒
actor RequestThrottle {
    let maxPerSecond: Int
    let maxRetries: Int
    let retryDelay: TimeInterval
    private var timestamps: [CFAbsoluteTime] = []
    private let log = Logger(subsystem: "com.chenpc.comic", category: "RequestThrottle")

    init(maxPerSecond: Int = 3, maxRetries: Int = 3, retryDelay: TimeInterval = 5) {
        self.maxPerSecond = maxPerSecond
        self.maxRetries   = maxRetries
        self.retryDelay   = retryDelay
    }

    /// 取得許可後才能發送請求。若 1 秒內已達上限，會自動等待。
    func acquire() async {
        let now = CFAbsoluteTimeGetCurrent()
        // 移除超過 1 秒的舊時戳
        timestamps.removeAll { now - $0 >= 1.0 }

        if timestamps.count >= maxPerSecond {
            // 等到最舊的時戳過期
            let oldest = timestamps[0]
            let waitTime = 1.0 - (now - oldest)
            if waitTime > 0 {
                log.debug("throttle: waiting \(String(format: "%.2f", waitTime))s")
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            // 遞迴再檢查一次（可能有其他 caller 插入）
            await acquire()
            return
        }

        timestamps.append(CFAbsoluteTimeGetCurrent())
    }

    /// 帶重試的資料抓取（最多 3 次，間隔 5 秒）
    /// nonisolated：僅 acquire() 持有 actor，block() 在 actor 外執行，允許並行下載
    nonisolated func fetchWithRetry(_ block: () async throws -> Data) async throws -> Data {
        var lastError: Error?
        for attempt in 1...maxRetries {
            await acquire()
            do {
                return try await block()   // actor 不持有，其他 Task 可同時下載
            } catch {
                lastError = error
                log.warning("attempt \(attempt)/3 failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        throw lastError!
    }
}

// MARK: - 向後相容

/// 漫畫櫃專用速率限制器（3 req/s）
typealias ManhuaguiThrottle = RequestThrottle
extension RequestThrottle {
    static let shared = RequestThrottle(maxPerSecond: 3, maxRetries: 3, retryDelay: 5)
}
