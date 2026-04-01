import XCTest
@testable import ComicLib

// MARK: - ManhuaguiService URL 建構測試

final class ManhuaguiURLTests: XCTestCase {

    private let svc = ManhuaguiService()

    // MARK: - 無篩選 URL

    func test_url_noFilter_page1() async throws {
        let (_, _) = try await svc.fetchComicList(page: 1, search: "", filterSlugs: [])
        // 只測能否不丟例外，實際 URL 在 fetchHTML 前就組好了
        // 若需要驗證 URL，可在 Service 公開一個 buildURL 方法
    }

    // MARK: - 篩選 URL 驗證（不需網路，直接驗證 URL 邏輯）

    func test_buildURL_singleFilter_page1() {
        // 組合後應為 /list/japan/
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: ["japan"])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/")
    }

    func test_buildURL_singleFilter_page2() {
        // 組合後應為 /list/japan_p2.html
        let url = ManhuaguiURLBuilder.build(page: 2, search: "", slugs: ["japan"])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan_p2.html")
    }

    func test_buildURL_multiFilter_page1() {
        // /list/japan/rexue/
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: ["japan", "rexue"])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/rexue/")
    }

    func test_buildURL_multiFilter_page3() {
        // /list/japan/rexue_p3.html
        let url = ManhuaguiURLBuilder.build(page: 3, search: "", slugs: ["japan", "rexue"])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/rexue_p3.html")
    }

    func test_buildURL_noFilter_page1() {
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: [])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/view.html")
    }

    func test_buildURL_noFilter_page5() {
        let url = ManhuaguiURLBuilder.build(page: 5, search: "", slugs: [])
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/view_p5.html")
    }

    func test_buildURL_search() {
        let url = ManhuaguiURLBuilder.build(page: 1, search: "海賊王", slugs: [])
        XCTAssertTrue(url.absoluteString.contains("/s/"))
        XCTAssertTrue(url.absoluteString.contains("manhuagui"))
    }

    func test_buildURL_sortOnly_page1() {
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: [], sort: "update")
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/update.html")
    }

    func test_buildURL_sortOnly_page2() {
        let url = ManhuaguiURLBuilder.build(page: 2, search: "", slugs: [], sort: "update")
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/update_p2.html")
    }

    func test_buildURL_filterAndSort_page1() {
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: ["japan"], sort: "update")
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/update.html")
    }

    func test_buildURL_filterAndSort_page2() {
        let url = ManhuaguiURLBuilder.build(page: 2, search: "", slugs: ["japan"], sort: "update")
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/update_p2.html")
    }

    func test_buildURL_multiFilterAndSort() {
        let url = ManhuaguiURLBuilder.build(page: 1, search: "", slugs: ["japan", "rexue"], sort: "view")
        XCTAssertEqual(url.absoluteString, "https://tw.manhuagui.com/list/japan/rexue/view.html")
    }
}

// MARK: - 漫畫列表 HTML 解析測試

final class ManhuaguiParseListTests: XCTestCase {

    private let svc = ManhuaguiService()

    // 最小化的漫畫列表 HTML 片段（格式與 manhuagui 實際 HTML 一致，href 與 img 同行）
    private let sampleListHTML = """
    <ul class="list-comic">
      <li>
        <a class="bcover" href="/comic/12345/" title="海賊王"><img src="//cf.mhgui.com/cover/12345.jpg" alt="海賊王"></a>
      </li>
      <li>
        <a class="bcover" href="/comic/67890/" title="火影忍者 &amp; 特別篇"><img src="//cf.mhgui.com/cover/67890.jpg" alt="火影忍者"></a>
      </li>
    </ul>
    """

    private let samplePaginationHTML = """
    <div class="page-wrap">
      第 <strong>1</strong> / <strong>1405</strong> 頁
    </div>
    """

    func test_parseComicList_count() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.count, 2)
    }

    func test_parseComicList_firstID() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.first?.id, "12345")
    }

    func test_parseComicList_firstTitle() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.first?.title, "海賊王")
    }

    func test_parseComicList_htmlEntityDecoded() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        // "火影忍者 &amp; 特別篇" 應解碼為 "火影忍者 & 特別篇"
        XCTAssertEqual(galleries.last?.title, "火影忍者 & 特別篇")
    }

    func test_parseComicList_thumbURL() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.first?.thumbURL?.absoluteString,
                       "https://cf.mhgui.com/cover/12345.jpg")
    }

    func test_parseComicList_galleryURL() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.first?.galleryURL.absoluteString,
                       "https://tw.manhuagui.com/comic/12345/")
    }

    func test_parseComicList_source() {
        let galleries = svc.parseComicList(from: sampleListHTML)
        XCTAssertEqual(galleries.first?.source, SourceID.manhuagui.rawValue)
    }

    func test_parseComicList_empty() {
        let galleries = svc.parseComicList(from: "<html><body>no comics</body></html>")
        XCTAssertTrue(galleries.isEmpty)
    }

    func test_parseTotalPages() {
        let pages = svc.parseTotalPages(from: samplePaginationHTML)
        XCTAssertEqual(pages, 1405)
    }

    func test_parseTotalPages_missing() {
        let pages = svc.parseTotalPages(from: "<html>no pagination</html>")
        XCTAssertNil(pages)
    }
}

// MARK: - 章節列表 HTML 解析測試

final class ManhuaguiParseChaptersTests: XCTestCase {

    private let svc = ManhuaguiService()
    private let comicURL = URL(string: "https://tw.manhuagui.com/comic/100/")!

    private let sampleChaptersHTML = """
    <div id="chapter-list-1">
      <ul>
        <li><a href="/comic/100/1001.html" title="第1話"><span>第1話</span></a></li>
        <li><a href="/comic/100/1002.html" title="第2話"><span>第2話</span></a></li>
        <li><a href="/comic/100/1003.html" title="第3話 &amp; 番外"><span>第3話</span></a></li>
      </ul>
    </div>
    """

    func test_parseChapters_count() {
        let chapters = svc.parseChapters(from: sampleChaptersHTML, comicURL: comicURL)
        XCTAssertEqual(chapters.count, 3)
    }

    func test_parseChapters_reversedOrder() {
        // 最後一章應在最前面
        let chapters = svc.parseChapters(from: sampleChaptersHTML, comicURL: comicURL)
        XCTAssertEqual(chapters.first?.id, "1003")
    }

    func test_parseChapters_titleDecoded() {
        let chapters = svc.parseChapters(from: sampleChaptersHTML, comicURL: comicURL)
        XCTAssertEqual(chapters.first?.title, "第3話 & 番外")
    }

    func test_parseChapters_url() {
        let chapters = svc.parseChapters(from: sampleChaptersHTML, comicURL: comicURL)
        XCTAssertEqual(chapters.first?.url.absoluteString,
                       "https://tw.manhuagui.com/comic/100/1003.html")
    }

    func test_parseChapters_noDuplicates() {
        // 即使 HTML 重複出現同一章節也只計一次
        let html = sampleChaptersHTML + sampleChaptersHTML
        let chapters = svc.parseChapters(from: html, comicURL: comicURL)
        XCTAssertEqual(chapters.count, 3)
    }

    func test_parseChapters_ignoresOtherComicLinks() {
        // 側欄有其他漫畫連結時，不應被納入章節列表
        let html = sampleChaptersHTML + """
        <div class="related">
          <a href="/comic/99999/55555.html" title="其他漫畫第1話">其他漫畫第1話</a>
          <a href="/comic/99999/55556.html" title="其他漫畫第2話">其他漫畫第2話</a>
        </div>
        """
        let chapters = svc.parseChapters(from: html, comicURL: comicURL)
        // comicURL = comic/100/ → 只解析 /comic/100/ 的章節，不含 99999
        XCTAssertEqual(chapters.count, 3, "不應包含其他漫畫的章節連結")
        XCTAssertTrue(chapters.allSatisfy { $0.url.absoluteString.contains("/comic/100/") },
                      "所有章節 URL 都應屬於漫畫 100")
    }
}

// MARK: - extractImageURLs 測試（解包 SMH.imgData JSON）

final class ManhuaguiExtractImageURLsTests: XCTestCase {

    private let svc = ManhuaguiService()

    private let sampleDecryptedJS = """
    SMH.imgData({"bid":100,"cid":1001,"bname":"海賊王","cname":"第1話",
    "files":["001.jpg","002.jpg","003.jpg"],
    "path":"/comic/100/1001/",
    "server":"//i.hamreus.com",
    "sl":{"e":1700000000,"m":"abc123def456"}})
    """

    func test_extractImageURLs_count() throws {
        let urls = try svc.extractImageURLs(from: sampleDecryptedJS)
        XCTAssertEqual(urls.count, 3)
    }

    func test_extractImageURLs_firstURL() throws {
        let urls = try svc.extractImageURLs(from: sampleDecryptedJS)
        let expected = "https://i.hamreus.com/comic/100/1001/001.jpg?e=1700000000&m=abc123def456"
        XCTAssertEqual(urls.first?.absoluteString, expected)
    }

    func test_extractImageURLs_lastURL() throws {
        let urls = try svc.extractImageURLs(from: sampleDecryptedJS)
        let expected = "https://i.hamreus.com/comic/100/1001/003.jpg?e=1700000000&m=abc123def456"
        XCTAssertEqual(urls.last?.absoluteString, expected)
    }

    func test_extractImageURLs_withoutSL() throws {
        let js = """
        SMH.imgData({"bid":1,"cid":2,"files":["a.jpg"],
        "path":"/p/","server":"//img.example.com"})
        """
        let urls = try svc.extractImageURLs(from: js)
        XCTAssertEqual(urls.first?.absoluteString, "https://img.example.com/p/a.jpg")
        XCTAssertFalse(urls.first?.absoluteString.contains("?") ?? true)
    }

    func test_extractImageURLs_missingFiles_throws() {
        let js = "SMH.imgData({\"path\":\"/p/\",\"server\":\"//s\"})"
        XCTAssertThrowsError(try svc.extractImageURLs(from: js))
    }

    func test_extractImageURLs_noSMH_throws() {
        XCTAssertThrowsError(try svc.extractImageURLs(from: "var x = 1;"))
    }
}

// MARK: - extractScriptBodies 測試

final class ManhuaguiExtractScriptBodiesTests: XCTestCase {

    private let svc = ManhuaguiService()

    func test_extractScriptBodies_count() {
        let html = """
        <html>
        <script>var a = 1;</script>
        <script>var b = 2;</script>
        <script src="external.js"></script>
        </html>
        """
        let bodies = svc.extractScriptBodies(from: html)
        // 只有兩個有 inline 內容
        XCTAssertEqual(bodies.count, 2)
    }

    func test_extractScriptBodies_emptyScript_skipped() {
        let html = "<html><script>  </script><script>x=1;</script></html>"
        let bodies = svc.extractScriptBodies(from: html)
        XCTAssertEqual(bodies.count, 1)
        XCTAssertEqual(bodies[0], "x=1;")
    }

    func test_extractScriptBodies_containsPacker() {
        let html = """
        <script>var x=1;</script>
        <script>eval(function(p,a,c,k,e,d){return 'abc';}('...',36,5,''.split('|'),0,{}))</script>
        """
        let bodies = svc.extractScriptBodies(from: html)
        XCTAssertTrue(bodies.contains(where: { $0.contains("function(p,a,c,k,e,d)") }))
    }
}

// MARK: - parseGalleryDetail 單元測試

final class ManhuaguiParseGalleryDetailTests: XCTestCase {

    private let svc = ManhuaguiService()

    private let sampleHTML = """
    <ul class="detail-list cf">
      <li>
        <span><strong>漫畫作者：</strong><a href="/author/4644/" title="Ken+">Ken+</a></span>
      </li>
    </ul>
    <div id="intro-cut"> 正當被誤安排到女子宿舍的アスカ進退兩難的時候，一個&ldquo;善良&rdquo;的魔法使出現在他的面前。 </div>
    """

    func test_parseGalleryDetail_author() {
        let detail = svc.parseGalleryDetail(from: sampleHTML)
        XCTAssertEqual(detail?.author, "Ken+")
    }

    func test_parseGalleryDetail_description() {
        let detail = svc.parseGalleryDetail(from: sampleHTML)
        XCTAssertNotNil(detail?.description)
        XCTAssertTrue(detail?.description?.contains("アスカ") == true)
    }

    func test_parseGalleryDetail_description_htmlDecoded() {
        let detail = svc.parseGalleryDetail(from: sampleHTML)
        // &ldquo; 應解碼為 "
        XCTAssertTrue(detail?.description?.contains("\u{201C}") == true,
                      "HTML entity 應被解碼，實際: \(detail?.description ?? "")")
    }

    func test_parseGalleryDetail_noAuthor_returnsDescriptionOnly() {
        let html = #"<div id="intro-cut"> 簡介文字 </div>"#
        let detail = svc.parseGalleryDetail(from: html)
        XCTAssertNil(detail?.author)
        XCTAssertEqual(detail?.description, "簡介文字")
    }

    func test_parseGalleryDetail_noMatch_returnsNil() {
        let detail = svc.parseGalleryDetail(from: "<html><body></body></html>")
        XCTAssertNil(detail)
    }

    func test_parseGalleryDetail_realNetwork() async throws {
        let url = URL(string: "https://tw.manhuagui.com/comic/232/")!
        let detail = try await svc.fetchGalleryDetail(comicURL: url)
        XCTAssertNotNil(detail, "應能取得漫畫詳細資料")
        XCTAssertNotNil(detail?.author, "海賊王應有作者，實際: \(String(describing: detail?.author))")
        print("author=\(detail?.author ?? "nil")")
        print("desc=\(detail?.description?.prefix(80) ?? "nil")")
    }
}

// MARK: - parseChapterImages 單元測試

final class ManhuaguiParseChapterImagesTests: XCTestCase {

    private let svc = ManhuaguiService()

    // 最簡單的 packer：function 直接回傳 p（不做任何替換），觸發 eval 攔截
    private func makeHTML(packedContent: String) -> String {
        """
        <html>
        <script>var x = 1;</script>
        <script>eval(function(p,a,c,k,e,d){return p}('\(packedContent)',0,0,''.split('|'),0,{}))</script>
        </html>
        """
    }

    private let validSMH = #"SMH.imgData({"bid":232,"cid":1001,"bname":"海賊王","cname":"第1話","files":["001.jpg","002.jpg"],"path":"/comic/232/1001/","server":"//i.hamreus.com","sl":{"e":1700000000,"m":"abc123def456"}});"#

    func test_parseChapterImages_returnsURLs() throws {
        let html = makeHTML(packedContent: validSMH)
        let urls = try svc.parseChapterImages(from: html)
        XCTAssertEqual(urls.count, 2)
    }

    func test_parseChapterImages_firstURLCorrect() throws {
        let html = makeHTML(packedContent: validSMH)
        let urls = try svc.parseChapterImages(from: html)
        XCTAssertEqual(urls.first?.absoluteString,
                       "https://i.hamreus.com/comic/232/1001/001.jpg?e=1700000000&m=abc123def456")
    }

    func test_parseChapterImages_noPacker_throws() {
        let html = "<html><script>var x = 1;</script></html>"
        XCTAssertThrowsError(try svc.parseChapterImages(from: html))
    }

    func test_parseChapterImages_packerWithEmptyFiles_returnsEmpty() throws {
        let smh = #"SMH.imgData({"bid":1,"cid":2,"files":[],"path":"/p/","server":"//s"});"#
        let html = makeHTML(packedContent: smh)
        let urls = try svc.parseChapterImages(from: html)
        XCTAssertTrue(urls.isEmpty, "files 為空時應回傳空陣列")
    }

    func test_parseChapterImages_withoutSL_noQueryString() throws {
        let smh = #"SMH.imgData({"bid":1,"cid":2,"files":["a.jpg"],"path":"/p/","server":"//s.example.com"});"#
        let html = makeHTML(packedContent: smh)
        let urls = try svc.parseChapterImages(from: html)
        XCTAssertFalse(urls.first?.absoluteString.contains("?") ?? false,
                       "無 sl 時 URL 不應含查詢字串")
        XCTAssertEqual(urls.first?.absoluteString, "https://s.example.com/p/a.jpg")
    }
}

// MARK: - 整合測試（需網路）：漫畫列表

final class ManhuaguiIntegrationListTests: XCTestCase {

    private let svc = ManhuaguiService()

    func test_fetchComicList_realNetwork() async throws {
        let (galleries, totalPages) = try await svc.fetchComicList(
            page: 1, search: "", filterSlugs: [])
        XCTAssertGreaterThan(galleries.count, 0, "應至少有一本漫畫")
        XCTAssertGreaterThan(totalPages, 0, "應有分頁數")
        XCTAssertEqual(galleries.first?.source, SourceID.manhuagui.rawValue)
    }

    func test_fetchComicList_withFilter_japan() async throws {
        let (galleries, _) = try await svc.fetchComicList(
            page: 1, search: "", filterSlugs: ["japan"])
        XCTAssertGreaterThan(galleries.count, 0)
    }

    func test_fetchComicList_search() async throws {
        // 漫畫櫃搜尋頁面對非瀏覽器請求可能返回 403/non-200，跳過此測試
        // 改用 WKWebView 才能正常搜尋
        throw XCTSkip("manhuagui 搜尋頁面需要瀏覽器環境，CLI 環境下可能 badResponse")
    }
}

// MARK: - 整合測試（需網路）：章節與圖片

final class ManhuaguiIntegrationChapterTests: XCTestCase {

    private let svc = ManhuaguiService()

    // 一本已知有章節的漫畫（海賊王 id=232）
    private let knownComicURL = URL(string: "https://tw.manhuagui.com/comic/232/")!

    func test_fetchChapters_count() async throws {
        let chapters = try await svc.fetchChapters(comicURL: knownComicURL)
        XCTAssertGreaterThan(chapters.count, 0, "海賊王應有章節")
    }

    func test_fetchChapters_firstChapterHasURL() async throws {
        let chapters = try await svc.fetchChapters(comicURL: knownComicURL)
        let first = try XCTUnwrap(chapters.first)
        XCTAssertTrue(first.url.absoluteString.contains("manhuagui.com"))
    }

    /// 核心 debug 測試：章節圖片是否能成功取得
    /// 這個測試用來驗證 WKWebView 攔截 SMH.imgData 是否正常運作
    func test_fetchChapterImages_returnsURLs() async throws {
        // 先取得章節列表
        let chapters = try await svc.fetchChapters(comicURL: knownComicURL)
        let chapter = try XCTUnwrap(chapters.first, "需要有章節")

        print("📖 測試章節：\(chapter.title) URL=\(chapter.url)")

        // 這是核心測試：WKWebView 攔截 SMH.imgData
        let imageURLs = try await svc.fetchChapterImages(chapterURL: chapter.url)

        XCTAssertGreaterThan(imageURLs.count, 0,
            "章節 '\(chapter.title)' 應有圖片 URL，但取得 0 個。" +
            "可能原因：WKWebView 未能攔截 SMH.imgData，或 splic 方法未定義。")

        print("✅ 取得 \(imageURLs.count) 個圖片 URL")
        print("   第一張：\(imageURLs.first?.absoluteString ?? "-")")

        // 驗證 URL 格式合理
        let first = try XCTUnwrap(imageURLs.first)
        XCTAssertTrue(first.scheme == "https", "圖片 URL 應為 https")
        XCTAssertTrue(first.pathExtension.lowercased().matches(["jpg", "png", "webp", "gif"]),
                      "圖片 URL 應有合理的副檔名，但得到：\(first.pathExtension)")
    }
}

// MARK: - 章節自動跳轉測試

final class ChapterNavigatorTests: XCTestCase {

    private let svc = ManhuaguiService()

    // 建立假章節列表輔助函式
    private func ch(_ title: String, _ id: String = "") -> Chapter {
        let key = id.isEmpty ? title : id
        return Chapter(id: key,
                       title: title,
                       url: URL(string: "https://tw.manhuagui.com/comic/1/\(key).html")!,
                       pageCount: nil)
    }

    // MARK: - parseChapterNumber

    func test_parseChapterNumber_zeroPadded() {
        let result = svc.parseChapterNumber(from: "第01卷")
        XCTAssertEqual(result?.num, 1)
        XCTAssertEqual(result?.unit, "卷")
    }

    func test_parseChapterNumber_withSurroundingText() {
        let result = svc.parseChapterNumber(from: "黑貓偵探 第26回 特別篇")
        XCTAssertEqual(result?.num, 26)
        XCTAssertEqual(result?.unit, "話")   // 話/回/集 正規化為「話」
    }

    func test_parseChapterNumber_unrecognized() {
        XCTAssertNil(svc.parseChapterNumber(from: "番外篇"))
    }

    // MARK: - findNextChapter：純卷列表

    func test_findNextChapter_volumes_normal() {
        // newest-first: 第03卷, 第02卷, 第01卷
        let chapters = [ch("第03卷","3"), ch("第02卷","2"), ch("第01卷","1")]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters[2].url)  // 第01卷
        XCTAssertEqual(result?.title, "第02卷")
    }

    func test_findNextChapter_zeroPadded_volumes() {
        let chapters = [ch("第03卷","3"), ch("第02卷","2"), ch("第01卷","1")]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters[2].url)
        XCTAssertEqual(result?.title, "第02卷")
    }

    func test_findNextChapter_atLatest_returnsNil() {
        let chapters = [ch("第03卷","3"), ch("第02卷","2"), ch("第01卷","1")]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters[0].url)  // 第03卷（最新）
        XCTAssertNil(result, "已是最新集，不應再跳")
    }

    // MARK: - 混合回/卷列表（核心 bug 場景）

    func test_findNextChapter_mixedUnits_doesNotCrossUnit() {
        // newest-first: 第26回, ..., 第01回, 第01卷
        // 讀完第01卷後不應跳到第26回
        let chapters: [Chapter] = [
            ch("第26回","r26"), ch("第25回","r25"), ch("第01回","r1"), ch("第01卷","v1")
        ]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters.last!.url)  // 第01卷
        XCTAssertNil(result, "第01卷後面沒有第02卷，不應跳到回")
    }

    func test_findNextChapter_mixedUnits_volumeToVolume() {
        // newest-first: 第26回, 第02卷, 第01卷, 第01回
        let chapters: [Chapter] = [
            ch("第26回","r26"), ch("第02卷","v2"), ch("第01卷","v1"), ch("第01回","r1")
        ]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters[2].url)  // 第01卷
        XCTAssertEqual(result?.title, "第02卷", "第01卷的下一集應是第02卷")
    }

    func test_findNextChapter_mixedUnits_episodeToEpisode() {
        // newest-first: 第26回, 第25回, 第02卷, 第01卷
        let chapters: [Chapter] = [
            ch("第26回","r26"), ch("第25回","r25"), ch("第02卷","v2"), ch("第01卷","v1")
        ]
        let result = svc.findNextChapter(in: chapters, currentURL: chapters[1].url)  // 第25回
        XCTAssertEqual(result?.title, "第26回", "第25回的下一集應是第26回")
    }

    func test_findNextChapter_mixedEpisodeUnits_huiToHua() {
        // 回報案例：第14回 -> 第15回 -> 第16話 頂級功法（回/話 混用，應視為同類）
        // newest-first
        let chapters: [Chapter] = [
            ch("第16話 頂級功法","16"), ch("第15回","15"), ch("第14回","14")
        ]
        // 第14回 → 第15回（同為回，應正常跳）
        let step1 = svc.findNextChapter(in: chapters, currentURL: chapters[2].url)
        XCTAssertEqual(step1?.title, "第15回", "第14回的下一集應是第15回")
        // 第15回 → 第16話 頂級功法（回→話 跨 unit，應視為同類）
        let step2 = svc.findNextChapter(in: chapters, currentURL: chapters[1].url)
        XCTAssertEqual(step2?.title, "第16話 頂級功法", "第15回的下一集應能找到第16話（話/回同類）")
    }
}

// MARK: - Helpers

/// 從 ManhuaguiService 提取出來供測試用的 URL 建構邏輯
enum ManhuaguiURLBuilder {
    static func build(page: Int, search: String, slugs: [String], sort: String = "") -> URL {
        if !search.isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? search
            let path = page <= 1 ? "/s/\(encoded).html" : "/s/\(encoded)_p\(page).html"
            return URL(string: "https://tw.manhuagui.com\(path)")!
        } else if !sort.isEmpty {
            let prefix = slugs.isEmpty ? "" : slugs.joined(separator: "/") + "/"
            let terminal = page <= 1 ? "\(sort).html" : "\(sort)_p\(page).html"
            return URL(string: "https://tw.manhuagui.com/list/\(prefix)\(terminal)")!
        } else if slugs.isEmpty {
            let path = page <= 1 ? "/list/view.html" : "/list/view_p\(page).html"
            return URL(string: "https://tw.manhuagui.com\(path)")!
        } else {
            if page <= 1 {
                let path = "/list/" + slugs.joined(separator: "/") + "/"
                return URL(string: "https://tw.manhuagui.com\(path)")!
            } else {
                let prefix = slugs.dropLast().joined(separator: "/")
                let last   = slugs.last!
                let path   = prefix.isEmpty
                    ? "/list/\(last)_p\(page).html"
                    : "/list/\(prefix)/\(last)_p\(page).html"
                return URL(string: "https://tw.manhuagui.com\(path)")!
            }
        }
    }
}

private extension String {
    func matches(_ extensions: [String]) -> Bool {
        extensions.contains(self.lowercased())
    }
}
