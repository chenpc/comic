import XCTest
@testable import ComicLib

// MARK: - ImageLoader Referer 測試

final class ImageLoaderRefererTests: XCTestCase {

    /// 驗證漫畫櫃封面圖用正確 Referer 可以 200
    func test_manhuagui_coverImageURL_withCorrectReferer_returns200() async throws {
        // 用漫畫列表頁的封面圖（由 parseComicList 解析，格式：//cf.mhgui.com/cpic/...）
        // 先從列表取一個真實 URL
        let svc = ManhuaguiService()
        let (galleries, _) = try await svc.fetchComicList(page: 1, search: "", filterSlugs: [])
        let thumbURL = try XCTUnwrap(galleries.first?.thumbURL, "封面圖 URL 不應為 nil")

        var req = URLRequest(url: thumbURL)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://tw.manhuagui.com", forHTTPHeaderField: "Referer")

        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(code, 200, "漫畫櫃封面圖用正確 Referer 應回 200，得到 \(code)")
    }

    /// 驗證 ImageLoader 對 manhuagui 圖片傳正確 Referer 可成功載入
    func test_imageLoader_manhuaguiURL_withCorrectReferer_succeeds() async throws {
        let svc = ManhuaguiService()
        let (galleries, _) = try await svc.fetchComicList(page: 1, search: "", filterSlugs: [])
        let thumbURL = try XCTUnwrap(galleries.first?.thumbURL)

        let img = await ImageLoader.shared.image(for: thumbURL, sourceID: .manhuagui)
        XCTAssertNotNil(img, "用正確 sourceID 載入漫畫櫃封面圖應成功（非 nil）")
    }
}

// MARK: - ImageLoader cacheKey / diskCacheSize

final class ImageLoaderCacheTests: XCTestCase {

    let loader = ImageLoader()

    func test_cacheKey_includesExtension() async {
        let url = URL(string: "https://example.com/image.jpg")!
        let key = await loader.cacheKey(for: url)
        XCTAssertTrue(key.hasSuffix(".jpg"), "key 應以 .jpg 結尾，得到 \(key)")
    }

    func test_cacheKey_noExtension_defaultsToJpg() async {
        let url = URL(string: "https://example.com/image")!
        let key = await loader.cacheKey(for: url)
        XCTAssertTrue(key.hasSuffix(".jpg"), "無副檔名應預設 .jpg，得到 \(key)")
    }

    func test_cacheKey_pngExtension() async {
        let url = URL(string: "https://example.com/image.png")!
        let key = await loader.cacheKey(for: url)
        XCTAssertTrue(key.hasSuffix(".png"))
    }

    func test_cacheKey_differentURLs_differentKeys() async {
        let url1 = URL(string: "https://example.com/image1.jpg")!
        let url2 = URL(string: "https://example.com/image2.jpg")!
        let key1 = await loader.cacheKey(for: url1)
        let key2 = await loader.cacheKey(for: url2)
        XCTAssertNotEqual(key1, key2)
    }

    func test_cacheKey_sameURL_sameKey() async {
        let url = URL(string: "https://example.com/image.jpg")!
        let key1 = await loader.cacheKey(for: url)
        let key2 = await loader.cacheKey(for: url)
        XCTAssertEqual(key1, key2)
    }

    func test_diskCacheSize_nonNegative() async {
        let size = await loader.diskCacheSize()
        XCTAssertGreaterThanOrEqual(size, 0)
    }
}

// MARK: - EHentaiPageCursorTests（驗證分頁 cursor 邏輯）

final class EHentaiPageCursorTests: XCTestCase {

    // 測試 parseNextCursor 能從 HTML 正確取出 cursor
    func test_parseNextCursor_found() {
        let html = """
        <div>
          <a id="unext" href="https://e-hentai.org/?next=2446671">&gt;</a>
        </div>
        """
        let svc = EHentaiService()
        let cursor = svc.parseNextCursor(from: html)
        XCTAssertEqual(cursor, "2446671")
    }

    func test_parseNextCursor_notFound() {
        let html = "<div>last page</div>"
        let svc = EHentaiService()
        let cursor = svc.parseNextCursor(from: html)
        XCTAssertNil(cursor)
    }

    func test_parseNextCursor_withSearchParams_ampersand() {
        // 搜尋時 URL 中 next 不是第一個參數：?f_search=test&next=9876543
        let html = """
        <a id="unext" href="https://e-hentai.org/?f_search=test&next=9876543">Next</a>
        """
        let svc = EHentaiService()
        let cursor = svc.parseNextCursor(from: html)
        XCTAssertEqual(cursor, "9876543")
    }

    func test_parseNextCursor_withSearchParams_htmlEntity() {
        // HTML entity 版本：&amp;next=
        let html = """
        <a id="unext" href="https://e-hentai.org/?f_search=test&amp;next=9876543">Next</a>
        """
        let svc = EHentaiService()
        let cursor = svc.parseNextCursor(from: html)
        XCTAssertEqual(cursor, "9876543")
    }
}
