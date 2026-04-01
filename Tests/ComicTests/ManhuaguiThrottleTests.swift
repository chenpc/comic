import Foundation
import Testing
@testable import ComicLib

@Suite("ManhuaguiThrottle")
struct ManhuaguiThrottleTests {

    @Test func acquire_limitsToThreePerSecond() async {
        let throttle = ManhuaguiThrottle.shared
        let start = CFAbsoluteTimeGetCurrent()
        // 發 6 次 acquire — 前 3 次應立即通過，第 4~6 次需等 ~1 秒
        for _ in 0..<6 {
            await throttle.acquire()
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        // 應至少花 ~1 秒（第 4 次要等第 1 次過期）
        #expect(elapsed >= 0.8, "6 acquires should take ≥ 0.8s, got \(elapsed)s")
    }

    @Test func fetchWithRetry_succeedsOnFirstTry() async throws {
        let data = try await ManhuaguiThrottle.shared.fetchWithRetry {
            return Data("ok".utf8)
        }
        #expect(String(data: data, encoding: .utf8) == "ok")
    }

    @Test func fetchWithRetry_retriesAndSucceeds() async throws {
        var attempts = 0
        let data = try await ManhuaguiThrottle.shared.fetchWithRetry {
            attempts += 1
            if attempts < 3 { throw URLError(.timedOut) }
            return Data("recovered".utf8)
        }
        #expect(attempts == 3)
        #expect(String(data: data, encoding: .utf8) == "recovered")
    }

    @Test func fetchWithRetry_failsAfterThreeAttempts() async {
        do {
            _ = try await ManhuaguiThrottle.shared.fetchWithRetry {
                throw URLError(.badServerResponse)
            }
            #expect(Bool(false), "should have thrown")
        } catch {
            #expect(error is URLError)
        }
    }
}
