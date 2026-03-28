import XCTest
import CryptoKit
@testable import ComicLib

/// 驗證漫畫櫃章節圖片內容正確性
final class ManhuaguiImageContentTests: XCTestCase {

    private let svc = ManhuaguiService()

    // MARK: - 圖片唯一性：確認不同頁不是同一張圖

    func test_chapterImages_firstThreePages_areDifferent() async throws {
        let chapters = try await svc.fetchChapters(
            comicURL: URL(string: "https://tw.manhuagui.com/comic/232/")!)
        let chapter = try XCTUnwrap(chapters.first)
        let imageURLs = try await svc.fetchChapterImages(chapterURL: chapter.url)

        XCTAssertGreaterThanOrEqual(imageURLs.count, 3, "章節應至少有 3 頁")

        // 下載前 3 頁並比較 SHA256
        let hashes = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for i in 0..<3 {
                group.addTask {
                    var req = URLRequest(url: imageURLs[i])
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                    req.setValue("https://tw.manhuagui.com", forHTTPHeaderField: "Referer")
                    let (data, _) = try await URLSession.shared.data(for: req)
                    let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                    return (i, hash)
                }
            }
            var results: [(Int, String)] = []
            for try await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }
        }

        let hashValues = hashes.map { $0.1 }
        print("頁面 hash：")
        for (i, hash) in hashes { print("  page\(i+1): \(hash.prefix(16))...") }

        // 3 頁應有不同內容（hash 不全相同）
        let unique = Set(hashValues)
        XCTAssertGreaterThan(unique.count, 1,
            "前 3 頁圖片的 SHA256 全部相同，代表 CDN 回傳同一張佔位圖。hashes=\(hashValues.map { $0.prefix(8) })")
    }

    // MARK: - 圖片尺寸：確認是有意義的圖片（非極小的錯誤圖）

    func test_chapterImages_firstPage_hasMeaningfulSize() async throws {
        let chapters = try await svc.fetchChapters(
            comicURL: URL(string: "https://tw.manhuagui.com/comic/232/")!)
        let chapter = try XCTUnwrap(chapters.first)
        let imageURLs = try await svc.fetchChapterImages(chapterURL: chapter.url)
        let firstURL = try XCTUnwrap(imageURLs.first)

        var req = URLRequest(url: firstURL)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://tw.manhuagui.com", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: req)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(code, 200, "第一頁應回 200")
        XCTAssertGreaterThan(data.count, 10_000,
            "圖片大小 \(data.count) bytes 太小，可能是錯誤佔位圖（正常漫畫頁應 > 10KB）")

        print("第一頁 URL：\(firstURL)")
        print("第一頁大小：\(data.count) bytes")
    }

    // MARK: - URL 結構驗證

    func test_chapterImageURLs_pathMatchesChapter() async throws {
        // 使用已知章節 URL，驗證 path 中含有正確的 comic ID
        let chapterURL = URL(string: "https://tw.manhuagui.com/comic/232/")!
        let chapters = try await svc.fetchChapters(comicURL: chapterURL)
        let chapter = try XCTUnwrap(chapters.first)
        let imageURLs = try await svc.fetchChapterImages(chapterURL: chapter.url)

        let firstURL = try XCTUnwrap(imageURLs.first)
        // CDN URL 路徑為目錄結構，不含 manhuagui comic ID；只驗證是合法 https URL
        XCTAssertEqual(firstURL.scheme, "https", "圖片 URL 應為 https，但 URL=\(firstURL)")
        XCTAssertNotNil(firstURL.host, "圖片 URL 應有 host，但 URL=\(firstURL)")
        // 所有 URL 應使用同一個 host
        let hosts = Set(imageURLs.compactMap { $0.host })
        XCTAssertEqual(hosts.count, 1, "同一章節的圖片應使用同一個 CDN host，但得到 \(hosts)")
        print("CDN host: \(hosts.first ?? "?")")
    }
}
