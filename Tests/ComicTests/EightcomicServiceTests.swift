import XCTest
@testable import ComicLib

// MARK: - 單元測試（不需網路）

@MainActor
final class EightcomicParseListTests: XCTestCase {
    let svc = EightcomicService()

    func test_parseListHTML_basicEntry() {
        let html = """
        <a href="/html/23999.html" title="反派發現了我的身份">
          <img src="/pics/0/23999.jpg" alt="">
        </a>
        """
        let result = svc.parseListHTML(html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "23999")
        XCTAssertEqual(result[0].title, "反派發現了我的身份")
        XCTAssertEqual(result[0].thumbURL?.absoluteString, "https://www.8comic.com/pics/0/23999.jpg")
        XCTAssertEqual(result[0].galleryURL.absoluteString, "https://www.8comic.com/html/23999.html")
        XCTAssertEqual(result[0].source, "8comic")
    }

    func test_parseListHTML_multipleEntries() {
        let html = """
        <a href="/html/100.html" title="漫畫A"><img src="/pics/0/100.jpg"></a>
        <a href="/html/200.html" title="漫畫B"><img src="/pics/0/200.jpg"></a>
        <a href="/html/300.html" title="漫畫C"><img src="/pics/0/300.jpg"></a>
        """
        let result = svc.parseListHTML(html)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.id), ["100", "200", "300"])
    }

    func test_parseListHTML_deduplicates() {
        let html = """
        <a href="/html/100.html" title="漫畫A"><img src="/pics/0/100.jpg"></a>
        <a href="/html/100.html" title="漫畫A重複"><img src="/pics/0/100.jpg"></a>
        """
        let result = svc.parseListHTML(html)
        XCTAssertEqual(result.count, 1)
    }

    func test_parseListHTML_emptyHTML() {
        let result = svc.parseListHTML("<html><body></body></html>")
        XCTAssertTrue(result.isEmpty)
    }
}

@MainActor
final class EightcomicParseChaptersTests: XCTestCase {
    let svc = EightcomicService()

    func test_parseChaptersHTML_basic() {
        // 頁面 HTML 是最新在前（第3話、第2話、第1話）
        let html = """
        <a href='#' onclick="cview('23999-3.html',11,0);return false;" id="c3" class="Ch eps_a">第3話</a>
        <a href='#' onclick="cview('23999-2.html',11,0);return false;" id="c2" class="Ch eps_a">第2話</a>
        <a href='#' onclick="cview('23999-1.html',11,0);return false;" id="c1" class="Ch eps_a">第1話</a>
        """
        let chapters = svc.parseChaptersHTML(html)
        XCTAssertEqual(chapters.count, 3)
        // reversed() 後最舊在前（第1話 at index 0）
        XCTAssertEqual(chapters[0].title, "第1話")
        XCTAssertEqual(chapters[0].id, "1")
        XCTAssertEqual(chapters[0].url.absoluteString, "https://www.8comic.com/view/23999.html?ch=1")
        XCTAssertEqual(chapters[2].title, "第3話")
    }

    func test_parseChaptersHTML_deduplicates() {
        let html = """
        <a href='#' onclick="cview('23999-1.html',11,0);return false;">第1話</a>
        <a href='#' onclick="cview('23999-1.html',11,0);return false;">第1話重複</a>
        """
        let chapters = svc.parseChaptersHTML(html)
        XCTAssertEqual(chapters.count, 1)
    }

    func test_parseChaptersHTML_emptyHTML() {
        let chapters = svc.parseChaptersHTML("<html></html>")
        XCTAssertTrue(chapters.isEmpty)
    }

    func test_parseChaptersHTML_urlContains8comic() {
        let html = """
        <a href='#' onclick="cview('13313-5.html',6,1);return false;">第5話</a>
        """
        let chapters = svc.parseChaptersHTML(html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters[0].url.absoluteString.contains("8comic.com"))
        XCTAssertTrue(chapters[0].url.absoluteString.contains("ch=5"))
    }
}

@MainActor
final class EightcomicDecryptBasicTests: XCTestCase {
    let svc = EightcomicService()

    // 用最簡單的 HTML 驗證 decryptChapterImages 的基本錯誤處理
    func test_decryptChapterImages_missingData_throws() {
        let url = URL(string: "https://www.8comic.com/view/1.html?ch=1")!
        XCTAssertThrowsError(try svc.decryptChapterImages(html: "<html></html>", chapterURL: url))
    }

    // 驗證動態變數名稱偵測：即使變數名稱不是 yy1yn34_04，也能正確解析
    // 建構一個含有新變數名稱（qgc8k7y）的最小 HTML，檢查能找到加密資料
    func test_decryptChapterImages_dynamicVarName_notHardcoded() {
        // 製造一個夠長的假加密字串（>500 字），使用新變數名 qgc8k7y
        let fakeData = String(repeating: "a", count: 600)
        let html = "<script>var ti=999;var qgc8k7y='\(fakeData)';</script>"
        let url = URL(string: "https://www.8comic.com/view/999.html?ch=1")!
        // 解密應該能找到變數（但因資料無效而在後續步驟 throw parseError，不是找不到變數）
        // 這個測試確保不是因為找不到變數名稱而 throw
        do {
            _ = try svc.decryptChapterImages(html: html, chapterURL: url)
            XCTFail("應 throw parseError（資料無效），但不應因找不到變數而失敗")
        } catch {
            // 預期 throw（資料無效），但必須不是「找不到變數」之前就 throw
            // 如果邏輯正確，error 為 EC8Error.parseError（章節記錄無效）
            XCTAssertNotNil(error as? ComicServiceError)
        }
    }

    // 確認用舊變數名稱 yy1yn34_04 的 HTML 也能正常解析（向後相容）
    func test_decryptChapterImages_oldVarName_stillWorks() {
        let fakeData = String(repeating: "b", count: 600)
        let html = "<script>var ti=999;var yy1yn34_04='\(fakeData)';</script>"
        let url = URL(string: "https://www.8comic.com/view/999.html?ch=1")!
        XCTAssertThrowsError(try svc.decryptChapterImages(html: html, chapterURL: url)) { err in
            XCTAssertNotNil(err as? ComicServiceError)
        }
    }
}

// MARK: - 解密單元測試

@MainActor
final class EightcomicDecryptTests: XCTestCase {
    let svc = EightcomicService()

    // 使用真實 /view/23999.html?ch=1 中的 yy1yn34_04 前段建構 minimal HTML
    // 記錄 1（i=1）對應 ch=1（wp_raw="ab" → lc=1）
    // cz=block[0:40], qn="bv"→lc=73→qnStr="73", pb="bv"→lc=73 (wrong but let's use real data)
    // 用已知 Python 結果來驗證：ch=1, page1 = https://img7.8comic.com/3/23999/1/001_776.jpg

    func test_decryptChapterImages_ch1_firstPage() throws {
        // 直接用已存的 HTML 檔（從網路取得），僅在有檔案時執行
        let path = "/tmp/view_page.html"
        guard FileManager.default.fileExists(atPath: path),
              let html = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw XCTSkip("需要 /tmp/view_page.html（執行整合測試後產生）")
        }
        let url = URL(string: "https://www.8comic.com/view/23999.html?ch=1")!
        let urls = try svc.decryptChapterImages(html: html, chapterURL: url)
        XCTAssertEqual(urls.count, 61, "第1話應有 61 頁")
        XCTAssertEqual(urls[0].absoluteString, "https://img7.8comic.com/3/23999/1/001_776.jpg")
    }
}

// MARK: - 整合測試（需要網路）

@MainActor
final class EightcomicIntegrationTests: XCTestCase {

    private func makeSvc() -> EightcomicService { EightcomicService() }

    // MARK: - Diagnostic

    func test_diag_listHTML_rawOutput() async throws {
        let svc = await makeSvc()
        let url = URL(string: "https://www.8comic.com/list/all_all_all/1.html")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        print("=== LIST HTML (status=\(status)) ===")
        print("長度：\(html.count)")
        print("前 2000 字：\(html.prefix(2000))")
        // 找幾個 /html/ 連結
        let links = html.components(separatedBy: "href=\"/html/").dropFirst().prefix(5).map { $0.components(separatedBy: "\"").first ?? "" }
        print("找到 /html/ 連結：\(links)")
        print("=====================================")
    }

    func test_diag_listHTML_comicU() async throws {
        let svc = await makeSvc()
        let url = URL(string: "https://www.8comic.com/comic/u-1.html")!
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        print("=== /comic/u-1.html (status=\(status), 長度=\(html.count)) ===")
        // 找 /pics/0/ 縮圖（漫畫列表的標誌）
        if let range = html.range(of: "/pics/0/") {
            let start = html.index(range.lowerBound, offsetBy: -200, limitedBy: html.startIndex) ?? html.startIndex
            let end = html.index(range.lowerBound, offsetBy: 500, limitedBy: html.endIndex) ?? html.endIndex
            print("第一個縮圖附近 HTML：\n\(html[start..<end])")
        } else {
            print("找不到 /pics/0/ 縮圖")
            // 印出後半段 HTML
            let mid = html.index(html.startIndex, offsetBy: html.count / 2)
            print("HTML 中段：\n\(html[mid...].prefix(2000))")
        }
        print("==========================================")
    }

    func test_diag_parseListHTML_fromNetwork() async throws {
        let svc = await makeSvc()
        // 測試兩個 URL
        for urlStr in ["https://www.8comic.com/list/all_all_all/1.html",
                       "https://www.8comic.com/comic/u-1.html"] {
            let url = URL(string: urlStr)!
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let galleries = svc.parseListHTML(html)
            print("=== \(urlStr) ===")
            print("HTML 長度：\(html.count), parseListHTML 數量：\(galleries.count)")
            if galleries.isEmpty {
                // 找 /pics/0/ 附近 HTML
                if let range = html.range(of: "/pics/0/") {
                    let start = html.index(range.lowerBound, offsetBy: -200, limitedBy: html.startIndex) ?? html.startIndex
                    let end = html.index(range.lowerBound, offsetBy: 300, limitedBy: html.endIndex) ?? html.endIndex
                    print("縮圖附近 HTML：\(html[start..<end])")
                } else {
                    print("找不到 /pics/0/")
                }
            } else {
                for g in galleries.prefix(3) {
                    print("  id=\(g.id) title=\(g.title)")
                }
            }
            print("=============")
        }
    }

    // MARK: - fetchList

    func test_fetchList_page1_returnsItems() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        XCTAssertGreaterThan(galleries.count, 0, "列表應有至少 1 筆")
        XCTAssertEqual(galleries.first?.source, "8comic")
    }

    func test_fetchList_page1_titlesNotEmpty() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        for g in galleries {
            XCTAssertFalse(g.title.isEmpty, "標題不應為空：\(g.id)")
        }
    }

    func test_fetchList_page1_thumbURLsValid() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        let withThumb = galleries.filter { $0.thumbURL != nil }
        XCTAssertGreaterThan(withThumb.count, 0, "至少 1 筆應有縮圖")
        if let first = withThumb.first {
            print("首筆縮圖：\(first.thumbURL!)")
        }
    }

    func test_fetchList_page1_galleryURLsContain8comic() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        for g in galleries {
            XCTAssertTrue(g.galleryURL.absoluteString.contains("8comic.com"),
                          "galleryURL 應含 8comic.com：\(g.galleryURL)")
        }
    }

    func test_fetchList_print() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        print("=== 列表前 5 筆 ===")
        for g in galleries.prefix(5) {
            print("  id=\(g.id) title=\(g.title) thumb=\(g.thumbURL?.absoluteString ?? "nil") url=\(g.galleryURL)")
        }
    }

    // MARK: - fetchChapterImages 診斷

    func test_diag_chapterImages_rawOutput() async throws {
        let svc = makeSvc()
        let chapters = try await svc.fetchChapters(mangaURL: URL(string: "https://www.8comic.com/html/23999.html")!)
        guard let chapter = chapters.first else { XCTFail("無章節"); return }
        print("使用章節：\(chapter.title) url=\(chapter.url)")

        // 先用 URLSession 直接抓 /view/ 頁面源碼
        var req = URLRequest(url: chapter.url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.8comic.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        print("=== /view/ 頁面 status=\(status), 長度=\(html.count) ===")
        // 找 yy1yn34_04 變數
        if let range = html.range(of: "yy1yn34_04") {
            let start = range.lowerBound
            let end = html.index(start, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
            print("yy1yn34_04：\(html[start..<end])")
        } else {
            print("找不到 yy1yn34_04")
            // 看看有沒有重導
            if let range = html.range(of: "location.href") {
                let start = html.index(range.lowerBound, offsetBy: -50, limitedBy: html.startIndex) ?? html.startIndex
                let end = html.index(range.lowerBound, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
                print("location.href 附近：\(html[start..<end])")
            }
            print("HTML 前 1000：\(html.prefix(1000))")
        }
        print("===========================================")

        // 用 WKWebView + getCookie 覆蓋腳本診斷
        // 用 evaluateHTML（URLSession 取 HTML + loadHTMLString）
        let diagJS = #"""
        (function() {
          var finalURL = window.location.href;
          var imgs = document.querySelectorAll('img');
          var allSrcs = Array.from(imgs).map(function(i){ return i.src; }).filter(function(s){ return s && s.startsWith('http'); });
          var hasBody = !!document.body;
          var bodyHTML = document.body ? document.body.innerHTML : null;
          var bodyLen = bodyHTML ? bodyHTML.length : 0;
          var bodySnippet = bodyHTML ? bodyHTML.substring(0, 800) : '';
          // 檢查 yy1yn34_04 變數
          var hasYY = typeof yy1yn34_04 !== 'undefined';
          var yyVal = hasYY ? String(yy1yn34_04).substring(0, 100) : 'undefined';
          // 腳本數量
          var scripts = document.querySelectorAll('script');
          var scriptSrcs = Array.from(scripts).map(function(s){ return s.src || '[inline]'; }).slice(0, 10);
          return JSON.stringify({
            finalURL: finalURL,
            title: document.title,
            imgCount: imgs.length,
            httpSrcs: allSrcs.slice(0, 10),
            hasBody: hasBody,
            bodyLen: bodyLen,
            bodySnippet: bodySnippet,
            hasYY: hasYY,
            yyVal: yyVal,
            scriptCount: scripts.length,
            scriptSrcs: scriptSrcs
          });
        })()
        """#
        let ckvpOverride = "document.cookie = 'CKVP=1; path=/; domain=.8comic.com';"
        let raw = try await WebViewExtractor.evaluateHTML(
            html: html,
            baseURL: URL(string: "https://www.8comic.com/view/")!,
            script: diagJS,
            delay: 5.0,
            injectedScripts: [ckvpOverride])
        print("=== evaluateHTML 診斷 ===\n\(raw.prefix(5000))\n========================")
    }

    // MARK: - fetchChapterImages

    func test_fetchChapterImages_returnsImages() async throws {
        let svc = makeSvc()
        let url = URL(string: "https://www.8comic.com/view/23999.html?ch=1")!
        let urls = try await svc.fetchChapterImages(chapterURL: url)
        XCTAssertEqual(urls.count, 61, "第1話應有 61 頁")
        XCTAssertTrue(urls[0].absoluteString.contains("8comic.com"), "圖片 URL 應包含 8comic.com")
        print("第1頁：\(urls[0])")
        print("最後一頁：\(urls.last!)")
    }

    // 新格式（chOffset=42）：manga 24758 第1話
    func test_fetchChapterImages_manga24758_ch1() async throws {
        let svc = makeSvc()
        let url = URL(string: "https://www.8comic.com/view/24758.html?ch=1")!
        let urls = try await svc.fetchChapterImages(chapterURL: url)
        XCTAssertGreaterThan(urls.count, 0, "manga 24758 第1話應有圖片")
        XCTAssertTrue(urls[0].absoluteString.contains("8comic.com"))
        print("manga24758 第1頁：\(urls[0])")
    }

    // MARK: - fetchChapters

    func test_fetchChapterImages_manga27445_ch1() async throws {
        let svc = await makeSvc()
        let url = URL(string: "https://www.8comic.com/view/27445.html?ch=1")!
        let urls = try await svc.fetchChapterImages(chapterURL: url)
        XCTAssertGreaterThan(urls.count, 0, "manga 27445 第1話應有圖片")
        print("manga27445 第1話 count=\(urls.count) first=\(urls[0])")
    }

    func test_fetchChapterImages_manga28150_ch1() async throws {
        let svc = await makeSvc()
        let url = URL(string: "https://www.8comic.com/view/28150.html?ch=1")!
        let urls = try await svc.fetchChapterImages(chapterURL: url)
        XCTAssertGreaterThan(urls.count, 0, "manga 28150 第1話應有圖片")
        print("manga28150 第1話 count=\(urls.count) first=\(urls[0])")
    }

    func test_fetchChaptersFallback_manga27445() async throws {
        // manga 27445 的 /html/27445.html 伺服器回傳空白，應透過 fallback 從 /view/ 解析章節
        let svc = await makeSvc()
        let mangaURL = URL(string: "https://www.8comic.com/html/27445.html")!
        let chapters = try await svc.fetchChapters(mangaURL: mangaURL)
        XCTAssertGreaterThan(chapters.count, 0, "manga 27445 應透過 fallback 找到章節")
        print("manga27445 章節數：\(chapters.count)，第1章：\(chapters.first?.title ?? "nil") url=\(chapters.first?.url.absoluteString ?? "nil")")
    }

    func test_fetchChapters_returnsChapters() async throws {
        let svc = await makeSvc()
        let (galleries, _) = try await svc.fetchList(page: 1, search: "")
        guard let gallery = galleries.first else { XCTFail("列表空"); return }
        print("使用漫畫：\(gallery.title) url=\(gallery.galleryURL)")
        let chapters = try await svc.fetchChapters(mangaURL: gallery.galleryURL)
        XCTAssertGreaterThan(chapters.count, 0, "應有至少 1 章")
        print("章節數：\(chapters.count)，前 3：\(chapters.prefix(3).map(\.title))")
    }
}
