import XCTest
@testable import ComicLib

// MARK: - 列表 HTML 解析測試

final class ManhuarenParseListTests: XCTestCase {

    private let svc = ManhuarenService()

    // 搜尋頁格式
    private let searchHTML = """
    <ul class="book-list">
      <li>
        <div class="book-list-cover">
          <a href="/manhua-haizeiwang-onepiece/" title="海贼王">
            <img class="book-list-cover-img" src="https://mhfm5hk.cdndm5.com/1/432/cover.jpeg" alt="海贼王">
          </a>
        </div>
        <div class="book-list-info">
          <p class="book-list-info-title">海贼王</p>
        </div>
      </li>
      <li>
        <div class="book-list-cover">
          <a href="/manhua-naruto/" title="火影忍者 &amp; 特別篇">
            <img class="book-list-cover-img" src="https://mhfm5hk.cdndm5.com/1/100/cover.jpeg" alt="火影忍者">
          </a>
        </div>
      </li>
    </ul>
    """

    // 分類/列表頁格式
    private let listHTML = """
    <ul class="manga-list-2">
      <li>
        <div class="manga-list-2-cover">
          <a href="/manhua-haizeiwang-onepiece/?from=%2fmanhua-list%2f">
            <img class="manga-list-2-cover-img" src="https://mhfm5hk.cdndm5.com/1/432/cover.jpeg">
          </a>
        </div>
        <p class="manga-list-2-title">
          <a href="/manhua-haizeiwang-onepiece/?from=%2fmanhua-list%2f">海贼王</a>
        </p>
      </li>
      <li>
        <div class="manga-list-2-cover">
          <a href="/manhua-naruto/?from=%2fmanhua-list%2f">
            <img class="manga-list-2-cover-img" src="https://mhfm5hk.cdndm5.com/1/100/cover.jpeg">
          </a>
        </div>
        <p class="manga-list-2-title">
          <a href="/manhua-naruto/?from=%2fmanhua-list%2f">火影忍者</a>
        </p>
      </li>
    </ul>
    """

    // MARK: - 搜尋頁格式

    func test_parseGalleryList_search_count() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertEqual(galleries.count, 2)
    }

    func test_parseGalleryList_search_title() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertEqual(galleries.first?.title, "海贼王")
    }

    func test_parseGalleryList_search_htmlEntityDecoded() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertEqual(galleries.last?.title, "火影忍者 & 特別篇")
    }

    func test_parseGalleryList_search_galleryURL() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertEqual(galleries.first?.galleryURL.absoluteString,
                       "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")
    }

    func test_parseGalleryList_search_thumbURL() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertNotNil(galleries.first?.thumbURL)
        XCTAssertTrue(galleries.first?.thumbURL?.absoluteString.contains("cdndm5.com") == true)
    }

    func test_parseGalleryList_search_source() {
        let galleries = svc.parseGalleryList(from: searchHTML)
        XCTAssertEqual(galleries.first?.source, SourceID.manhuaren.rawValue)
    }

    // MARK: - 分類頁格式

    func test_parseGalleryList_list_count() {
        let galleries = svc.parseGalleryList(from: listHTML)
        XCTAssertEqual(galleries.count, 2)
    }

    func test_parseGalleryList_list_title() {
        let galleries = svc.parseGalleryList(from: listHTML)
        XCTAssertEqual(galleries.first?.title, "海贼王")
    }

    func test_parseGalleryList_list_galleryURL_stripsFromParam() {
        let galleries = svc.parseGalleryList(from: listHTML)
        // ?from=... 應被移除，只保留乾淨的 path
        XCTAssertEqual(galleries.first?.galleryURL.absoluteString,
                       "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")
    }

    func test_parseGalleryList_list_id_noSlashes() {
        let galleries = svc.parseGalleryList(from: listHTML)
        // id 不應含斜線
        XCTAssertFalse(galleries.first?.id.contains("/") == true)
    }

    func test_parseGalleryList_empty() {
        let galleries = svc.parseGalleryList(from: "<html><body>no comics</body></html>")
        XCTAssertTrue(galleries.isEmpty)
    }
}

// MARK: - 章節 HTML 解析測試

final class ManhuarenParseChaptersTests: XCTestCase {

    private let svc = ManhuarenService()

    private let sampleHTML = """
    <ul class="detail-list-1 detail-list-select" id="detail-list-select-1">
      <li><a href="/m1767265/" title="愤怒" class="chapteritem">第1177话</a></li>
      <li><a href="/m1761105/" title="雷竜" class="chapteritem">第1175话</a></li>
      <li><a href="/m100001/" title="第1話 &amp; 番外" class="chapteritem">第1話 &amp; 番外</a></li>
    </ul>
    """

    func test_parseChapters_count() {
        let chapters = svc.parseChapters(from: sampleHTML)
        XCTAssertEqual(chapters.count, 3)
    }

    func test_parseChapters_reversedOrder() {
        // HTML 倒序（最新在前），parseChapters 應反轉為正序（第1話在前）
        let chapters = svc.parseChapters(from: sampleHTML)
        XCTAssertEqual(chapters.first?.title, "第1話 & 番外")
    }

    func test_parseChapters_latestAtEnd() {
        let chapters = svc.parseChapters(from: sampleHTML)
        XCTAssertEqual(chapters.last?.title, "第1177话")
    }

    func test_parseChapters_id() {
        let chapters = svc.parseChapters(from: sampleHTML)
        // 最後一章（最新）id 應為 "1767265"
        XCTAssertEqual(chapters.last?.id, "1767265")
    }

    func test_parseChapters_url() {
        let chapters = svc.parseChapters(from: sampleHTML)
        XCTAssertEqual(chapters.last?.url.absoluteString,
                       "https://www.manhuaren.com/m1767265/")
    }

    func test_parseChapters_htmlEntityDecoded() {
        let chapters = svc.parseChapters(from: sampleHTML)
        XCTAssertEqual(chapters.first?.title, "第1話 & 番外")
    }

    func test_parseChapters_empty() {
        let chapters = svc.parseChapters(from: "<html><body></body></html>")
        XCTAssertTrue(chapters.isEmpty)
    }

    func test_parseChapters_ignoresNonChapterLinks() {
        let html = """
        <a href="/manhua-haizeiwang-onepiece/" class="detaillink">漫畫首頁</a>
        <a href="/m1767265/" class="chapteritem">第1177话</a>
        """
        let chapters = svc.parseChapters(from: html)
        XCTAssertEqual(chapters.count, 1)
    }
}

// MARK: - 章節圖片 JS Packer 解碼測試

final class ManhuarenExtractImagesTests: XCTestCase {

    private let svc = ManhuarenService()

    // 模擬章節頁的 newImgs script（直接賦值，測試解析邏輯而不測 packer 解碼）
    private let packedScript = """
    <script type="036b424b25dc6b2e9ee9625c-text/javascript">var newImgs=['https://manhua1040zjcdn123.cdndm5.com/1767265/432/1_9464.jpg?a=0&b=abc&type=1','https://manhua1040zjcdn123.cdndm5.com/1767265/432/2_8896.jpg?a=0&b=abc&type=1','https://manhua1040zjcdn123.cdndm5.com/1767265/432/3_7334.jpg?a=0&b=abc&type=1'];</script>
    """

    private let noScriptHTML = "<html><body>no packed js here</body></html>"

    func test_extractImages_count() throws {
        let urls = try svc.extractImages(from: packedScript)
        XCTAssertEqual(urls.count, 3)
    }

    func test_extractImages_firstURL_isHTTPS() throws {
        let urls = try svc.extractImages(from: packedScript)
        XCTAssertTrue(urls.first?.scheme == "https")
    }

    func test_extractImages_urlsContainCDN() throws {
        let urls = try svc.extractImages(from: packedScript)
        for url in urls {
            XCTAssertTrue(url.absoluteString.contains("cdndm5.com"),
                          "URL 應包含 cdndm5.com CDN: \(url)")
        }
    }

    func test_extractImages_missingPackedJS_throws() {
        XCTAssertThrowsError(try svc.extractImages(from: noScriptHTML))
    }

    func test_extractImages_emptyNewImgs_throws() {
        // newImgs 存在但為空陣列
        let html = "<script type=\"x\">var newImgs=[];</script>"
        XCTAssertThrowsError(try svc.extractImages(from: html))
    }
}
