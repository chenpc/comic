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
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
        XCTAssertEqual(galleries.count, 2)
    }

    func test_parseGalleryList_search_title() {
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
        XCTAssertEqual(galleries.first?.title, "海贼王")
    }

    func test_parseGalleryList_search_htmlEntityDecoded() {
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
        XCTAssertEqual(galleries.last?.title, "火影忍者 & 特別篇")
    }

    func test_parseGalleryList_search_galleryURL() {
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
        XCTAssertEqual(galleries.first?.galleryURL.absoluteString,
                       "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")
    }

    func test_parseGalleryList_search_thumbURL() {
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
        XCTAssertNotNil(galleries.first?.thumbURL)
        XCTAssertTrue(galleries.first?.thumbURL?.absoluteString.contains("cdndm5.com") == true)
    }

    func test_parseGalleryList_search_source() {
        let galleries = svc.parseGalleryList(from: searchHTML, isSearch: true)
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

    // 新版格式：標題在 <p class="detail-list-2-info-title"> 裡（如妖神記）
    // 真實頁面倒序（最新在前）
    private let newFormatHTML = """
    <a href="/m426477/" class="chapteritem">
        <div class="detail-list-2-cover">
            <img class="detail-list-2-cover-img" src="https://example.com/cover2.jpg">
        </div>
        <div class="detail-list-2-info">
            <p class="detail-list-2-info-title">第2回 魔法</p>
        </div>
    </a>
    <a href="/m426475/" class="chapteritem">
        <div class="detail-list-2-cover">
            <img class="detail-list-2-cover-img" src="https://example.com/cover.jpg">
        </div>
        <div class="detail-list-2-info">
            <p class="detail-list-2-info-title">第1回 重生</p>
            <p class="detail-list-2-info-subtitle">2016-11-11</p>
        </div>
    </a>
    """

    func test_parseChapters_newFormat_count() {
        let chapters = svc.parseChapters(from: newFormatHTML)
        XCTAssertEqual(chapters.count, 2)
    }

    func test_parseChapters_newFormat_title() {
        let chapters = svc.parseChapters(from: newFormatHTML)
        // 頁面倒序，反轉後第一章應為 "第1回 重生"
        XCTAssertEqual(chapters.first?.title, "第1回 重生")
    }

    func test_parseChapters_newFormat_id() {
        let chapters = svc.parseChapters(from: newFormatHTML)
        XCTAssertEqual(chapters.first?.id, "426475")
    }

    func test_parseChapters_newFormat_url() {
        let chapters = svc.parseChapters(from: newFormatHTML)
        XCTAssertEqual(chapters.first?.url.absoluteString, "https://www.manhuaren.com/m426475/")
    }

    // 付費章節：含 detail-list-2-info-right 鎖頭圖示，標題應加 "$$ " 前綴
    private let paidChapterHTML = """
    <a href="/m1768649/" class="chapteritem">
        <div class="detail-list-2-info">
            <p class="detail-list-2-info-title">第515回 新对手（上）</p>
            <img class="detail-list-2-info-right" src="https://css123hk.cdndm5.com/v202508200911/manhuaren/images/mobile/detail-list-logo-right.png">
        </div>
    </a>
    <a href="/m426475/" class="chapteritem">
        <div class="detail-list-2-info">
            <p class="detail-list-2-info-title">第1回 重生</p>
        </div>
    </a>
    """

    func test_parseChapters_paidChapter_hasPrefix() {
        let chapters = svc.parseChapters(from: paidChapterHTML)
        // 付費章節（m1768649）在頁面前，反轉後在最後
        XCTAssertTrue(chapters.last?.title.hasPrefix("$$ ") == true,
                      "付費章節標題應有 '$$ ' 前綴，實際: \(chapters.last?.title ?? "")")
    }

    func test_parseChapters_freeChapter_noPrefix() {
        let chapters = svc.parseChapters(from: paidChapterHTML)
        XCTAssertFalse(chapters.first?.title.hasPrefix("$$ ") == true,
                       "免費章節不應有 '$$ ' 前綴")
    }

    func test_parseChapters_paidChapter_titleContent() {
        let chapters = svc.parseChapters(from: paidChapterHTML)
        XCTAssertEqual(chapters.last?.title, "$$ 第515回 新对手（上）")
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

// MARK: - parseGalleryDetail 測試

final class ManhuarenParseGalleryDetailTests: XCTestCase {

    private let svc = ManhuarenService()

    // 結構1：作者：直接後接 <a>（URL 含多個查詢參數）
    func test_author_inlineColon() {
        let html = """
        <p>作者：<a href="/search/?title=尾田荣一郎&language=1&f=2">尾田荣一郎</a></p>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertEqual(detail?.author, "尾田荣一郎", "inline 作者：<a> 應解析正確")
    }

    // 結構2：作者：</span> 後接 <a>（span 包住 label）
    func test_author_afterClosingSpan() {
        let html = """
        <p><span class="info-label">作者：</span><a href="/search/?title=鸟山明&language=1&f=2">鸟山明</a></p>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertEqual(detail?.author, "鸟山明", "作者：</span><a> 應解析正確")
    }

    // 結構3：<em>作者</em> 後接 <a>
    func test_author_emTag() {
        let html = """
        <p><em>作者</em><a href="/search/?title=岸本齐史&language=1&f=2">岸本齐史</a></p>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertEqual(detail?.author, "岸本齐史", "<em>作者</em><a> 應解析正確")
    }

    // 結構4：有換行和空白
    func test_author_withWhitespace() {
        let html = """
        <p class="detail-list-1-item">
          作者：
          <a href="/search/?title=作者名&language=1&f=2">作者名</a>
        </p>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertEqual(detail?.author, "作者名", "有換行空白時應能正確解析")
    }

    // 結構5：多個作者（取第一個）
    func test_author_multiple_takesFirst() {
        let html = """
        <p>作者：<a href="/search/?title=作者A&language=1&f=2">作者A</a>
               <a href="/search/?title=作者B&language=1&f=2">作者B</a></p>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertEqual(detail?.author, "作者A", "多作者時應取第一個")
    }

    // 結構6：無作者
    func test_author_notFound_returnsNil() {
        let html = "<html><body><p>漫畫簡介</p></body></html>"
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertNil(detail?.author, "無作者時應為 nil")
    }

    // 簡介解析
    func test_description_detailDescClass() {
        let html = """
        <div class="detail-desc">這是一部關於海賊的漫畫。主角是路飛。</div>
        """
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertNotNil(detail?.description, "應能解析 detail-desc 簡介")
        XCTAssertTrue(detail?.description?.contains("海賊") == true)
    }
}

// MARK: - parseAJAXParams 測試（間接覆蓋 parseJSVar）

final class ManhuarenParseAJAXParamsTests: XCTestCase {

    private let svc = ManhuarenService()

    // 含所有已知 JS 變數的 HTML 片段
    private let fullHTML = """
    <script>
    var categoryid = '1';
    var tagid = '2';
    var status = '3';
    var usergroup = '4';
    var pay = '0';
    var areaid = '5';
    var sort = '20';
    var iscopyright = 'true';
    </script>
    """

    func test_parseAJAXParams_categoryid() {
        let params = svc.parseAJAXParams(from: fullHTML, slug: "")
        XCTAssertEqual(params["categoryid"], "1")
    }

    func test_parseAJAXParams_tagid() {
        let params = svc.parseAJAXParams(from: fullHTML, slug: "")
        XCTAssertEqual(params["tagid"], "2")
    }

    func test_parseAJAXParams_sort() {
        let params = svc.parseAJAXParams(from: fullHTML, slug: "")
        XCTAssertEqual(params["sort"], "20")
    }

    func test_parseAJAXParams_iscopyright_true_convertsTo1() {
        let params = svc.parseAJAXParams(from: fullHTML, slug: "")
        XCTAssertEqual(params["iscopyright"], "1")
    }

    func test_parseAJAXParams_iscopyright_false_convertsTo0() {
        let html = "<script>var iscopyright = 'false';</script>"
        let params = svc.parseAJAXParams(from: html, slug: "")
        XCTAssertEqual(params["iscopyright"], "0")
    }

    func test_parseAJAXParams_missingVars_usesDefaults() {
        // HTML 中沒有任何 JS 變數，應回傳預設值
        let params = svc.parseAJAXParams(from: "<html></html>", slug: "")
        XCTAssertEqual(params["categoryid"], "0")
        XCTAssertEqual(params["tagid"], "0")
        XCTAssertEqual(params["sort"], "10")
        XCTAssertEqual(params["iscopyright"], "0")
    }

    func test_parseAJAXParams_partialVars_overridesOnly() {
        // 只有部分變數，其他保持預設
        let html = "<script>var categoryid = '7'; var sort = '5';</script>"
        let params = svc.parseAJAXParams(from: html, slug: "")
        XCTAssertEqual(params["categoryid"], "7")
        XCTAssertEqual(params["sort"], "5")
        XCTAssertEqual(params["tagid"], "0")  // 預設值
    }
}

// MARK: - parseAJAXResponse 測試

final class ManhuarenParseAJAXResponseTests: XCTestCase {

    private let svc = ManhuarenService()

    private let sampleJSON = """
    {
      "UpdateComicItems": [
        {
          "UrlKey": "manhua-haizeiwang-onepiece",
          "Title": "海贼王",
          "ShowPicUrlB": "https://mhfm5hk.cdndm5.com/1/432/cover.jpeg"
        },
        {
          "UrlKey": "manhua-naruto",
          "Title": "火影忍者 &amp; 特別篇",
          "ShowPicUrlB": "https://mhfm5hk.cdndm5.com/1/100/cover.jpeg"
        }
      ]
    }
    """.data(using: .utf8)!

    func test_parseAJAXResponse_count() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.count, 2)
    }

    func test_parseAJAXResponse_id() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.first?.id, "manhua-haizeiwang-onepiece")
    }

    func test_parseAJAXResponse_title() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.first?.title, "海贼王")
    }

    func test_parseAJAXResponse_htmlEntityDecoded() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.last?.title, "火影忍者 & 特別篇")
    }

    func test_parseAJAXResponse_thumbURL() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.first?.thumbURL?.absoluteString,
                       "https://mhfm5hk.cdndm5.com/1/432/cover.jpeg")
    }

    func test_parseAJAXResponse_galleryURL() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.first?.galleryURL.absoluteString,
                       "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")
    }

    func test_parseAJAXResponse_source() throws {
        let galleries = try svc.parseAJAXResponse(data: sampleJSON)
        XCTAssertEqual(galleries.first?.source, SourceID.manhuaren.rawValue)
    }

    func test_parseAJAXResponse_missingURLKey_skipped() throws {
        let json = """
        {"UpdateComicItems": [{"Title": "無 UrlKey"}]}
        """.data(using: .utf8)!
        let galleries = try svc.parseAJAXResponse(data: json)
        XCTAssertTrue(galleries.isEmpty, "缺少 UrlKey 的 item 應被略過")
    }

    func test_parseAJAXResponse_invalidJSON_throws() {
        let badData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try svc.parseAJAXResponse(data: badData))
    }

    func test_parseAJAXResponse_missingUpdateComicItems_throws() {
        let json = #"{"status": "ok"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try svc.parseAJAXResponse(data: json))
    }

    func test_parseAJAXResponse_emptyItems_returnsEmpty() throws {
        let json = #"{"UpdateComicItems": []}"#.data(using: .utf8)!
        let galleries = try svc.parseAJAXResponse(data: json)
        XCTAssertTrue(galleries.isEmpty)
    }
}

// MARK: - 整合測試（需要網路）

final class ManhuarenIntegrationTests: XCTestCase {

    private let svc = ManhuarenService()

    // MARK: - 列表

    func test_fetchList_page1_returns21Items() async throws {
        let (galleries, _) = try await svc.fetchComicList(page: 1, search: "", slug: "")
        XCTAssertEqual(galleries.count, 21, "第 1 頁應有 21 筆")
        XCTAssertEqual(galleries.first?.title, "海贼王")
    }

    func test_fetchList_page2_differentFromPage1() async throws {
        let (p1, _) = try await svc.fetchComicList(page: 1, search: "", slug: "")
        let (p2, _) = try await svc.fetchComicList(page: 2, search: "", slug: "")
        XCTAssertEqual(p2.count, 21, "第 2 頁應有 21 筆")
        XCTAssertNotEqual(p1.map(\.id), p2.map(\.id), "page1 與 page2 內容應不同")
    }

    func test_fetchChapters_haizeiwang_returnsChapters() async throws {
        let url = URL(string: "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")!
        let chapters = try await svc.fetchChapters(galleryURL: url)
        XCTAssertGreaterThan(chapters.count, 100, "海贼王應有 100+ 章")
        XCTAssertTrue(chapters.last?.title.contains("1177") == true || chapters.count > 900,
                      "最新章節應含 1177")
    }

    func test_fetchGalleryDetail_haizeiwang() async throws {
        let url = URL(string: "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")!
        let detail = await svc.fetchGalleryDetail(galleryURL: url)
        XCTAssertNotNil(detail, "應能取得漫畫詳細資料")
        XCTAssertNotNil(detail?.author, "海賊王應有作者資料，實際: \(String(describing: detail?.author))")
        print("✅ author=\(detail?.author ?? "nil")")
        print("✅ description=\(detail?.description?.prefix(80) ?? "nil")")
    }

    // 抓原始 HTML 供 debug 用
    func test_fetchGalleryDetail_printRawHTML() async throws {
        let url = URL(string: "https://www.manhuaren.com/manhua-haizeiwang-onepiece/")!
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Referer": "https://www.manhuaren.com/",
        ]
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""
        print("📄 HTML length=\(html.count)")
        // 找所有「作者」出現位置並印出上下文
        var searchRange = html.startIndex..<html.endIndex
        var found = false
        while let range = html.range(of: "作者", range: searchRange) {
            found = true
            let ctxStart = max(html.startIndex, html.index(range.lowerBound, offsetBy: -30, limitedBy: html.startIndex) ?? html.startIndex)
            let ctxEnd   = min(html.endIndex,   html.index(range.upperBound, offsetBy: 150, limitedBy: html.endIndex)   ?? html.endIndex)
            print("--- 作者 context ---\n\(html[ctxStart..<ctxEnd])\n")
            searchRange = range.upperBound..<html.endIndex
        }
        if !found { print("⚠️ HTML 中找不到「作者」字串") }
    }

    func test_fetchChapterImages_returnsURLs() async throws {
        let url = URL(string: "https://www.manhuaren.com/m1767265/")!
        let images = try await svc.fetchChapterImages(chapterURL: url)
        XCTAssertGreaterThan(images.count, 0, "應有至少 1 張圖片")
        XCTAssertTrue(images.first?.scheme == "https")
    }
}
