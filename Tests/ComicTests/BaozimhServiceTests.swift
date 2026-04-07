import XCTest
@testable import ComicLib

// MARK: - 單元測試（不需網路）

// 測資來源：https://www.baozimh.com/comic/yaoshenji-taxuedongman
private let slug = "yaoshenji-taxuedongman"

// MARK: - 漫畫列表解析

@MainActor
final class BaozimhParseGalleryListTests: XCTestCase {
    let svc = BaozimhService.shared

    func test_basicEntry() {
        let html = """
        <a href="/comic/yaoshenji-taxuedongman" class="comics-card__poster">
          <amp-img src="https://static-tw.baozimh.com/cover/yaoshenji-taxuedongman.jpg.thumb.jpg" layout="fill"></amp-img>
        </a>
        <a href="/comic/yaoshenji-taxuedongman" class="comics-card__info">
          <h3 class="comics-card__title">妖神記</h3>
        </a>
        """
        let result = svc.parseGalleryList(html: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "yaoshenji-taxuedongman")
        XCTAssertEqual(result[0].title, "妖神記")
        XCTAssertEqual(result[0].thumbURL?.absoluteString,
                       "https://static-tw.baozimh.com/cover/yaoshenji-taxuedongman.jpg.thumb.jpg")
        XCTAssertEqual(result[0].galleryURL.absoluteString,
                       "https://www.baozimh.com/comic/yaoshenji-taxuedongman")
        XCTAssertEqual(result[0].source, "baozimh")
    }

    func test_multipleEntries() {
        let html = """
        <a href="/comic/yaoshenji-taxuedongman" class="comics-card__poster">
          <amp-img src="https://static-tw.baozimh.com/cover/yaoshenji-taxuedongman.jpg.thumb.jpg"></amp-img>
        </a>
        <a href="/comic/yaoshenji-taxuedongman" class="comics-card__info"><h3>妖神記</h3></a>
        <a href="/comic/another-manga" class="comics-card__poster">
          <amp-img src="https://static-tw.baozimh.com/cover/another-manga.jpg.thumb.jpg"></amp-img>
        </a>
        <a href="/comic/another-manga" class="comics-card__info"><h3>另一部漫畫</h3></a>
        """
        let result = svc.parseGalleryList(html: html)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "yaoshenji-taxuedongman")
        XCTAssertEqual(result[1].id, "another-manga")
    }

    func test_emptyHTML() {
        XCTAssertTrue(svc.parseGalleryList(html: "<html><body></body></html>").isEmpty)
    }
}

// MARK: - 總頁數解析

@MainActor
final class BaozimhParseTotalPagesTests: XCTestCase {
    let svc = BaozimhService.shared

    func test_findsMaxPage() {
        let html = """
        <a href="/classify?type=0&page=1">1</a>
        <a href="/classify?type=0&page=3">3</a>
        <a href="/classify?type=0&page=5">5</a>
        """
        XCTAssertEqual(svc.parseTotalPages(html: html), 5)
    }

    func test_singlePage() {
        let html = "<a href=\"/classify?type=0&page=1\">1</a>"
        XCTAssertEqual(svc.parseTotalPages(html: html), 1)
    }

    func test_noPage_returnsOne() {
        XCTAssertEqual(svc.parseTotalPages(html: "<html></html>"), 1)
    }
}

// MARK: - 章節列表解析

@MainActor
final class BaozimhParseChaptersTests: XCTestCase {
    let svc = BaozimhService.shared

    // HTML 最新在前（slot 2→1→0），解析後應升冪排列
    private let chaptersHTML = """
    <a href="/user/page_direct?comic_id=yaoshenji-taxuedongman&amp;section_slot=0&amp;chapter_slot=2" class="comics-chapters__item">
      <div style="flex: 1;" class="comics-chapters__item-title"><span data-v-abc>第3話</span></div>
    </a>
    <a href="/user/page_direct?comic_id=yaoshenji-taxuedongman&amp;section_slot=0&amp;chapter_slot=1" class="comics-chapters__item">
      <div style="flex: 1;" class="comics-chapters__item-title"><span data-v-abc>第2話</span></div>
    </a>
    <a href="/user/page_direct?comic_id=yaoshenji-taxuedongman&amp;section_slot=0&amp;chapter_slot=0" class="comics-chapters__item">
      <div style="flex: 1;" class="comics-chapters__item-title"><span data-v-abc>第1話</span></div>
    </a>
    """

    func test_count() {
        XCTAssertEqual(svc.parseChapters(html: chaptersHTML, slug: slug).count, 3)
    }

    // 排序：HTML 最新在前，解析後 index=0 應是最舊（slot 最小）
    func test_sortedAscending_index0IsOldest() {
        let chapters = svc.parseChapters(html: chaptersHTML, slug: slug)
        XCTAssertEqual(chapters[0].title, "第1話")
        XCTAssertEqual(chapters[1].title, "第2話")
        XCTAssertEqual(chapters[2].title, "第3話")
    }

    // 非連續 slot（5,2,8,1,3）— 排序後應為 1,2,3,5,8
    func test_sortedAscending_nonContiguousSlots() {
        let html = """
        <a href="/user/page_direct?comic_id=\(slug)&amp;section_slot=0&amp;chapter_slot=5">
          <div><span>E</span></div></a>
        <a href="/user/page_direct?comic_id=\(slug)&amp;section_slot=0&amp;chapter_slot=2">
          <div><span>B</span></div></a>
        <a href="/user/page_direct?comic_id=\(slug)&amp;section_slot=0&amp;chapter_slot=8">
          <div><span>H</span></div></a>
        <a href="/user/page_direct?comic_id=\(slug)&amp;section_slot=0&amp;chapter_slot=1">
          <div><span>A</span></div></a>
        <a href="/user/page_direct?comic_id=\(slug)&amp;section_slot=0&amp;chapter_slot=3">
          <div><span>C</span></div></a>
        """
        let chapters = svc.parseChapters(html: html, slug: slug)
        XCTAssertEqual(chapters.map { Int($0.id.components(separatedBy: "_").last ?? "") ?? -1 },
                       [1, 2, 3, 5, 8])
    }

    func test_ids() {
        let chapters = svc.parseChapters(html: chaptersHTML, slug: slug)
        XCTAssertEqual(chapters[0].id, "\(slug)/0_0")
        XCTAssertEqual(chapters[1].id, "\(slug)/0_1")
        XCTAssertEqual(chapters[2].id, "\(slug)/0_2")
    }

    func test_urlDecodesAmpersand() {
        let url0 = svc.parseChapters(html: chaptersHTML, slug: slug)[0].url.absoluteString
        XCTAssertTrue(url0.contains("baozimh.com"))
        XCTAssertTrue(url0.contains("comic_id=\(slug)"), "實際：\(url0)")
        XCTAssertTrue(url0.contains("chapter_slot=0"), "實際：\(url0)")
        XCTAssertFalse(url0.contains("&amp;"))
    }

    func test_emptyHTML() {
        XCTAssertTrue(svc.parseChapters(html: "<html></html>", slug: slug).isEmpty)
    }
}

// MARK: - 章節圖片解析

@MainActor
final class BaozimhParseImageURLsTests: XCTestCase {
    let svc = BaozimhService.shared

    private let imageHTML = """
    <script type="application/json">{"url": "https://img.baozimh.com/tp/yaoshenji-taxuedongman/1/0001.jpg"}</script>
    <script type="application/json">{"url": "https://img.baozimh.com/tp/yaoshenji-taxuedongman/1/0002.jpg"}</script>
    <script type="application/json">{"url": "https://img.baozimh.com/tp/yaoshenji-taxuedongman/1/0003.jpg"}</script>
    """

    func test_count() {
        XCTAssertEqual(svc.parseImageURLs(html: imageHTML).count, 3)
    }

    func test_firstURL() {
        XCTAssertEqual(svc.parseImageURLs(html: imageHTML)[0].absoluteString,
                       "https://img.baozimh.com/tp/yaoshenji-taxuedongman/1/0001.jpg")
    }

    func test_allHTTPS() {
        for url in svc.parseImageURLs(html: imageHTML) {
            XCTAssertEqual(url.scheme, "https")
        }
    }

    func test_withSpaceAfterColon() {
        let html = "<script type=\"application/json\">{\"url\":  \"https://img.baozimh.com/test/001.jpg\"}</script>"
        let urls = svc.parseImageURLs(html: html)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].absoluteString, "https://img.baozimh.com/test/001.jpg")
    }

    func test_ignoresNonHTTPS() {
        // http:// URL 不應被解析（pattern 只抓 https://）
        let html = "<script>{\"url\": \"http://img.baozimh.com/tp/test/1.jpg\"}</script>"
        XCTAssertTrue(svc.parseImageURLs(html: html).isEmpty)
    }

    func test_emptyHTML() {
        XCTAssertTrue(svc.parseImageURLs(html: "<html></html>").isEmpty)
    }
}

// MARK: - 推廣章節偵測（純邏輯，不需網路）

@MainActor
final class BaozimhIsPromoChapterTests: XCTestCase {
    let svc = BaozimhService.shared

    // 所有圖片均屬於其他漫畫 → 推廣章節
    func test_promoWhenAllImagesAreWrongComic() {
        let urls = [
            URL(string: "https://s1.bzcdn.net/scomic/other-manga/0/1-abc/1.jpg")!,
            URL(string: "https://s1.bzcdn.net/scomic/other-manga/0/1-abc/2.jpg")!,
        ]
        XCTAssertTrue(svc.isPromoChapter(comicID: slug, imageURLs: urls))
    }

    // 至少一張圖屬於正確漫畫 → 非推廣
    func test_notPromoWhenAnyImageMatchesComicID() {
        let urls = [
            URL(string: "https://s1.bzcdn.net/scomic/other-manga/0/1-abc/1.jpg")!,
            URL(string: "https://s2.bzcdn.net/scomic/\(slug)/0/1-xyz/1.jpg")!,
        ]
        XCTAssertFalse(svc.isPromoChapter(comicID: slug, imageURLs: urls))
    }

    // 所有圖片均屬於正確漫畫 → 非推廣
    func test_notPromoWhenAllImagesMatchComicID() {
        let urls = [
            URL(string: "https://s2.bzcdn.net/scomic/\(slug)/0/1-xyz/1.jpg")!,
            URL(string: "https://s2.bzcdn.net/scomic/\(slug)/0/1-xyz/2.jpg")!,
        ]
        XCTAssertFalse(svc.isPromoChapter(comicID: slug, imageURLs: urls))
    }

    // 空圖片列表 → 不視為推廣（尚未載入，不應誤判）
    func test_notPromoWhenImageURLsEmpty() {
        XCTAssertFalse(svc.isPromoChapter(comicID: slug, imageURLs: []))
    }

    // comicID 為 nil（章節 URL 無 comic_id 參數）→ 不檢查
    func test_notPromoWhenComicIDNil() {
        let urls = [URL(string: "https://s1.bzcdn.net/scomic/other-manga/0/1.jpg")!]
        XCTAssertFalse(svc.isPromoChapter(comicID: nil, imageURLs: urls))
    }

    // comicID 為空字串 → 不檢查（避免誤判）
    func test_notPromoWhenComicIDEmpty() {
        let urls = [URL(string: "https://s1.bzcdn.net/scomic/other-manga/0/1.jpg")!]
        XCTAssertFalse(svc.isPromoChapter(comicID: "", imageURLs: urls))
    }
}

// MARK: - 漫畫詳細解析

@MainActor
final class BaozimhParseGalleryDetailTests: XCTestCase {
    let svc = BaozimhService.shared

    private let detailHTML = """
    <html><head>
    <meta name="og:novel:author" content="郭斌">
    <meta name="description" content="少年聶離，天生廢靈根，卻因獲得神秘傳承，踏上妖師之路。">
    <meta name="og:novel:status" content="連載中">
    </head><body></body></html>
    """

    func test_author() {
        XCTAssertEqual(svc.parseGalleryDetail(html: detailHTML).author, "郭斌")
    }

    func test_description() {
        XCTAssertEqual(svc.parseGalleryDetail(html: detailHTML).description,
                       "少年聶離，天生廢靈根，卻因獲得神秘傳承，踏上妖師之路。")
    }

    func test_status() {
        XCTAssertEqual(svc.parseGalleryDetail(html: detailHTML).status, "連載中")
    }

    func test_missingFields() {
        let detail = svc.parseGalleryDetail(html: "<html></html>")
        XCTAssertNil(detail.author)
        XCTAssertNil(detail.description)
        XCTAssertNil(detail.status)
    }
}

// MARK: - DownloadManager 註冊驗證

final class BaozimhDownloadManagerRegistrationTests: XCTestCase {

    func test_baozimh_isChapterBased_afterRegistration() {
        // BaozimhSource 的 hasChapters = true，ComicApp.init 會註冊
        // 此測試在 test bundle（無 ComicApp.init）執行，直接手動註冊後確認
        DownloadManager.register(.baozimh, handlers: .init(
            hasChapters: true,
            fetchChapters: { _ in [] },
            fetchImageURLs: { _ in [] }
        ))
        XCTAssertTrue(DownloadManager.isChapterBased(.baozimh))
    }

    func test_ehentai_isNotChapterBased_afterRegistration() {
        DownloadManager.register(.ehentai, handlers: .init(
            hasChapters: false,
            fetchChapters: { _ in [] },
            fetchImageURLs: { _ in [] }
        ))
        XCTAssertFalse(DownloadManager.isChapterBased(.ehentai))
    }
}

// MARK: - 速率限制（單元，不需網路）

final class BaozimhThrottleTests: XCTestCase {

    func test_throttle_limitsToThreePerSecond() async {
        let throttle = RequestThrottle(maxPerSecond: 3, maxRetries: 1, retryDelay: 0)
        let start = CFAbsoluteTimeGetCurrent()
        // 發 6 次 acquire — 前 3 次立即通過，第 4~6 次需等約 1 秒
        for _ in 0..<6 { await throttle.acquire() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertGreaterThanOrEqual(elapsed, 0.8,
            "6 次 acquire 應至少花 0.8s，實際：\(String(format: "%.2f", elapsed))s")
    }

    func test_throttle_firstThreeAreImmediate() async {
        let throttle = RequestThrottle(maxPerSecond: 3, maxRetries: 1, retryDelay: 0)
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<3 { await throttle.acquire() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 0.5,
            "前 3 次 acquire 應立即完成，實際：\(String(format: "%.2f", elapsed))s")
    }

    func test_fetchWithRetry_succeedsOnFirstTry() async throws {
        let throttle = RequestThrottle(maxPerSecond: 3, maxRetries: 3, retryDelay: 0)
        let data = try await throttle.fetchWithRetry { Data("ok".utf8) }
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    func test_fetchWithRetry_retriesOnFailure() async throws {
        let throttle = RequestThrottle(maxPerSecond: 3, maxRetries: 3, retryDelay: 0)
        var attempts = 0
        let data = try await throttle.fetchWithRetry {
            attempts += 1
            if attempts < 3 { throw URLError(.timedOut) }
            return Data("recovered".utf8)
        }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(String(data: data, encoding: .utf8), "recovered")
    }

    func test_fetchWithRetry_throwsAfterMaxRetries() async {
        let throttle = RequestThrottle(maxPerSecond: 10, maxRetries: 3, retryDelay: 0)
        do {
            _ = try await throttle.fetchWithRetry { throw URLError(.badServerResponse) }
            XCTFail("應 throw")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}

// MARK: - 整合測試（需要網路）

@MainActor
final class BaozimhIntegrationTests: XCTestCase {

    func test_fetchChapters_yaoshenji() async throws {
        let url = URL(string: "https://www.baozimh.com/comic/yaoshenji-taxuedongman")!
        let chapters = try await BaozimhService.shared.fetchChapters(galleryURL: url)
        XCTAssertGreaterThan(chapters.count, 100, "妖神記應有 100 話以上")
        // index=0 應是最舊的章節（slot 最小）
        let firstSlot = Int(chapters[0].id.components(separatedBy: "_").last ?? "") ?? -1
        let lastSlot  = Int(chapters.last!.id.components(separatedBy: "_").last ?? "") ?? -1
        XCTAssertLessThan(firstSlot, lastSlot, "章節應升冪排列，index=0 最舊")
        print("[baozimh_test] 妖神記章節數：\(chapters.count)，第1話：\(chapters.first?.title ?? "nil")")
    }

    func test_fetchImageURLs_ch1_correctComic() async throws {
        let galleryURL = URL(string: "https://www.baozimh.com/comic/yaoshenji-taxuedongman")!
        let chapters = try await BaozimhService.shared.fetchChapters(galleryURL: galleryURL)
        guard let ch1 = chapters.first else { XCTFail("無章節"); return }
        let urls = try await BaozimhService.shared.fetchImageURLs(chapterURL: ch1.url)
        XCTAssertGreaterThan(urls.count, 0, "第1話應有圖片")
        XCTAssertTrue(urls[0].absoluteString.hasPrefix("https://"))
        // 圖片應屬於正確漫畫，不應誤偵測為推廣章節
        let hasCorrectComic = urls.contains { $0.absoluteString.contains("yaoshenji-taxuedongman") }
        XCTAssertTrue(hasCorrectComic, "第1話圖片應屬於妖神記")
        print("[baozimh_test] 第1話圖片數：\(urls.count)，第1頁：\(urls[0])")
    }

    func test_fetchImageURLs_promoSlot_throws() async {
        // slot=954 是推廣章節，應 throw parseError
        let url = URL(string: "https://www.baozimh.com/user/page_direct?comic_id=yaoshenji-taxuedongman&section_slot=0&chapter_slot=954")!
        do {
            _ = try await BaozimhService.shared.fetchImageURLs(chapterURL: url)
            XCTFail("應 throw parseError")
        } catch ComicServiceError.parseError {
            // 預期
        } catch {
            XCTFail("預期 parseError，實際：\(error)")
        }
    }
}
