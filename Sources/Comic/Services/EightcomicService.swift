import Foundation
import os.log


@MainActor
final class EightcomicService: ComicService {
    static let shared = EightcomicService()

    private let log = Logger(subsystem: "com.chenpc.comic", category: "EightcomicService")
    private let base = "https://www.8comic.com"

    let referer = "https://www.8comic.com/"
    nonisolated let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Image Extraction JS

    let imageExtractionJS = #"""
    (function() {
      try {
        var seen = {}, result = [];
        var imgs = document.querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) {
          var src = imgs[i].src || '';
          if (src && /^https?:/.test(src) && /\.(jpg|jpeg|png|webp)/i.test(src) && !seen[src]) {
            seen[src] = true;
            result.push(src);
          }
        }
        if (result.length === 0) {
          return JSON.stringify({ success: false, reason: 'no imgs', title: document.title });
        }
        return JSON.stringify({ success: true, images: result });
      } catch(e) { return JSON.stringify({ success: false, error: e.toString() }); }
    })()
    """#

    // MARK: - List

    /// category: "all"/1/2/... status: "all"/"ongoing"/"complete"  sort: "all"/"hot"/"new"
    func fetchList(page: Int, search: String, category: String = "all", status: String = "all", sort: String = "all") async throws -> (galleries: [Gallery], totalPages: Int) {
        let url: URL
        if !search.isEmpty {
            let enc = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            url = URL(string: "\(base)/search/?searchkey=\(enc)")!
        } else if category == "all" && status == "all" && sort == "all" {
            // 無篩選時用 /comic/u- 格式（含 title 屬性，解析穩定）
            url = URL(string: "\(base)/comic/u-\(page).html")!
        } else {
            url = URL(string: "\(base)/list/\(category)_\(status)_\(sort)/\(page).html")!
        }
        log.info("fetchList url=\(url)")
        let html = try await fetchHTML(url: url)
        let galleries = parseListHTML(html)
        log.debug("fetchList count=\(galleries.count)")
        return (galleries, galleries.isEmpty ? page : page + 1)
    }

    func parseListHTML(_ html: String) -> [Gallery] {
        var seen = Set<String>()
        var results: [Gallery] = []

        // 格式一：/comic/ 頁面 — <a href="/html/ID.html" title="TITLE">
        let titlePattern = #"<a\s+href="(/html/(\d+)\.html)"\s+title="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: titlePattern) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard match.numberOfRanges >= 4,
                      let hrefRange  = Range(match.range(at: 1), in: html),
                      let idRange    = Range(match.range(at: 2), in: html),
                      let titleRange = Range(match.range(at: 3), in: html) else { continue }
                let href    = String(html[hrefRange])
                let mangaID = String(html[idRange])
                let title   = String(html[titleRange])
                guard !title.isEmpty, !seen.contains(mangaID) else { continue }
                seen.insert(mangaID)
                let thumbURL = URL(string: "\(base)/pics/0/\(mangaID).jpg")
                guard let galleryURL = URL(string: "\(base)\(href)") else { continue }
                results.append(Gallery(id: mangaID, token: mangaID, title: title,
                                       thumbURL: thumbURL, pageCount: nil, category: nil,
                                       uploader: nil, source: SourceID.eightcomic.rawValue,
                                       galleryURL: galleryURL))
            }
        }

        // 格式二：/list/ 頁面 — <a href="/html/ID.html" ...><img alt="TITLE">（不跨越 </a>）
        if results.isEmpty {
            let altPattern = #"href="/html/(\d+)\.html"[^>]*>(?:(?!</a>)[\s\S])*?<img[^>]+alt="([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: altPattern) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    guard match.numberOfRanges >= 3,
                          let idRange    = Range(match.range(at: 1), in: html),
                          let titleRange = Range(match.range(at: 2), in: html) else { continue }
                    let mangaID = String(html[idRange])
                    let title   = String(html[titleRange])
                    guard !title.isEmpty, !seen.contains(mangaID) else { continue }
                    seen.insert(mangaID)
                    let thumbURL = URL(string: "\(base)/pics/0/\(mangaID).jpg")
                    guard let galleryURL = URL(string: "\(base)/html/\(mangaID).html") else { continue }
                    results.append(Gallery(id: mangaID, token: mangaID, title: title,
                                           thumbURL: thumbURL, pageCount: nil, category: nil,
                                           uploader: nil, source: SourceID.eightcomic.rawValue,
                                           galleryURL: galleryURL))
                }
            }
        }

        return results
    }

    // MARK: - Chapters

    func fetchChapters(mangaURL: URL) async throws -> [Chapter] {
        log.info("fetchChapters url=\(mangaURL)")
        let html = try await fetchHTML(url: mangaURL)
        let chapters = parseChaptersHTML(html)
        if !chapters.isEmpty { return chapters }

        // Fallback：/html/ID.html 空白時，從 /view/ID.html 取得章節總數
        log.info("fetchChapters fallback to view page for \(mangaURL)")
        print("[8comic] fetchChapters: html page empty, trying view fallback for \(mangaURL)")
        return try await fetchChaptersFallback(mangaURL: mangaURL)
    }

    /// 當 /html/ID.html 沒有章節列表時，改從 /view/ID.html 解析章節總數並合成
    func fetchChaptersFallback(mangaURL: URL) async throws -> [Chapter] {
        // 取得 manga ID
        guard let mangaID = mangaURL.pathComponents.last.flatMap({ name -> String? in
            let s = name.replacingOccurrences(of: ".html", with: "")
            return s.isEmpty ? nil : s
        }) else { return [] }

        let viewURL = URL(string: "\(base)/view/\(mangaID).html")!
        let viewHTML = try await fetchHTML(url: viewURL)

        // 從 if(chv>0&&chv<=N) 或 if(chv>=1&&chv<=N) 取得最大章節數
        guard let maxCh: Int = {
            let pattern = #"chv<=(\d+)"#
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: viewHTML, range: NSRange(viewHTML.startIndex..., in: viewHTML)),
                  let r = Range(m.range(at: 1), in: viewHTML),
                  let n = Int(viewHTML[r]) else { return nil }
            return n
        }(), maxCh > 0 else {
            print("[8comic] fetchChaptersFallback: cannot find chapter count for \(mangaID)")
            return []
        }

        print("[8comic] fetchChaptersFallback: mangaID=\(mangaID) maxCh=\(maxCh)")
        log.info("fetchChaptersFallback mangaID=\(mangaID) maxCh=\(maxCh)")

        return (1...maxCh).map { ch in
            let url = URL(string: "\(base)/view/\(mangaID).html?ch=\(ch)")!
            return Chapter(id: "\(ch)", title: "第\(ch)話", url: url, pageCount: nil)
        }
    }

    func parseChaptersHTML(_ html: String) -> [Chapter] {
        let pattern = #"onclick="cview\('(\d+)-(\d+)\.html'[^)]*\)[^"]*"[^>]*>([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var seen = Set<String>()
        var chapters: [Chapter] = []
        for match in matches {
            guard match.numberOfRanges >= 4,
                  let comicIDRange = Range(match.range(at: 1), in: html),
                  let chapNumRange = Range(match.range(at: 2), in: html),
                  let titleRange   = Range(match.range(at: 3), in: html) else { continue }
            let comicID = String(html[comicIDRange])
            let chapNum = String(html[chapNumRange])
            let title   = String(html[titleRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard !title.isEmpty, !seen.contains(chapNum) else { continue }
            seen.insert(chapNum)
            guard let chapterURL = URL(string: "\(base)/view/\(comicID).html?ch=\(chapNum)") else { continue }
            chapters.append(Chapter(id: chapNum, title: title, url: chapterURL, pageCount: nil))
        }
        return chapters.reversed()  // 最舊在前
    }

    // MARK: - Chapter Images

    func fetchChapterImages(chapterURL: URL) async throws -> [URL] {
        log.info("fetchChapterImages url=\(chapterURL)")
        print("[8comic] fetchChapterImages url=\(chapterURL)")
        let html = try await fetchHTML(url: chapterURL)
        print("[8comic] html length=\(html.count)")
        // 印出 HTML 前 200 字 + 找到的長變數
        let snippet = String(html.prefix(200))
        print("[8comic] html prefix=\(snippet)")
        let urls = try decryptChapterImages(html: html, chapterURL: chapterURL)
        print("[8comic] success count=\(urls.count) first=\(urls.first?.absoluteString ?? "nil")")
        return urls
    }

    /// 從 /view/ 頁面 HTML 直接解密圖片 URL（不需 WKWebView）
    func decryptChapterImages(html: String, chapterURL: URL) throws -> [URL] {
        // 1. 擷取加密資料
        func regexCapture(_ pattern: String, in s: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
        // 動態偵測加密資料變數（變數名稱會隨版本混淆，找最長的單引號字串變數）
        guard let yy: String = {
            guard let re = try? NSRegularExpression(pattern: #"var \w+='([^']{500,})'"#) else { return nil }
            let ns = html as NSString
            var best: String? = nil
            re.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: html) else { return }
                let v = String(html[r])
                if best == nil || v.count > best!.count { best = v }
            }
            return best
        }(), !yy.isEmpty else {
            print("[8comic] FAIL step1: no encrypted var found (html len=\(html.count))")
            throw ComicServiceError.parseError
        }
        print("[8comic] step1 ok: encryptedData len=\(yy.count)")

        // 2. 擷取 ti（漫畫 ID）
        guard let tiStr = regexCapture(#"var ti=(\d+)"#, in: html),
              let ti = Int(tiStr) else {
            print("[8comic] FAIL step2: var ti not found")
            throw ComicServiceError.parseError
        }
        print("[8comic] step2 ok: ti=\(ti)")

        // 3. 從 URL query 取得章節號
        guard let chStr = URLComponents(url: chapterURL, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "ch" })?.value,
              let ch = Int(chStr) else {
            print("[8comic] FAIL step3: ch not in URL \(chapterURL)")
            throw ComicServiceError.parseError
        }
        print("[8comic] step3 ok: ch=\(ch)")

        // 4. 解密函數
        let az = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        func lc(_ s: Substring) -> Int? {
            guard s.count == 2, let a = az.firstIndex(of: s.first!),
                  let b = az.firstIndex(of: s.last!) else { return nil }
            let ai = az.distance(from: az.startIndex, to: a)
            let bi = az.distance(from: az.startIndex, to: b)
            if s.first == "Z" { return 8000 + bi }
            return ai * 52 + bi
        }
        func hexDecode(_ hex: Substring) -> String {
            var result = ""
            var i = hex.startIndex
            while hex.distance(from: i, to: hex.endIndex) >= 2 {
                let j = hex.index(i, offsetBy: 2)
                if let code = UInt32(hex[i..<j], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                }
                i = j
            }
            return result
        }
        func tvj(_ n: Int) -> String {
            let pos = yy.index(yy.endIndex, offsetBy: -(47 + n * 6))
            let end = yy.index(pos, offsetBy: 6)
            return hexDecode(yy[pos..<end])
        }

        let t1 = tvj(1)  // "jpg"
        let t2 = tvj(2)  // "ic."
        let t3 = tvj(3)  // "com"
        let t4 = tvj(4)  // "img"

        // 5. mm / nn 函數
        func mm(_ p: Int) -> Int { (((p - 1) / 10) % 10) + ((p - 1) % 10 * 3) }
        func nn(_ n: Int) -> String { String(format: "%03d", n) }

        // 6. 動態偵測各欄位的 byte offset（各版本混淆方式不同）
        // 偵測策略：
        //   ch:     VAR==ch
        //   server: FUNC(VAR, 0, 1) 用來取第一個字元構成 domain
        //   cz:     FUNC(VAR, mm(...), 3) 用來取圖片代碼
        //   pages:  ps=VAR 頁數賦值

        // 建立 var VARNAME = lc(yy, i*47 + OFFSET, 2) 的對應（帶 len=2）
        var varToOffset: [String: Int] = [:]
        if let re = try? NSRegularExpression(
            pattern: #"var (\w+)=lc\(\w+\(\w+,i\*[^,]+\+(\d+),2\)\)"#) {
            re.enumerateMatches(in: html, range: NSRange(html.startIndex..., in: html)) { m, _, _ in
                guard let m, m.numberOfRanges >= 3,
                      let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let off = Int(html[r2]) else { return }
                varToOffset[String(html[r1])] = off
            }
        }
        // 建立 var VARNAME = lc(yy, i*47 + OFFSET)（不帶 len，用於 cz）
        var varToOffsetNoLen: [String: Int] = [:]
        if let re = try? NSRegularExpression(
            pattern: #"var (\w+)=lc\(\w+\(\w+,i\*[^,]+\+(\d+)\)\)"#) {
            re.enumerateMatches(in: html, range: NSRange(html.startIndex..., in: html)) { m, _, _ in
                guard let m, m.numberOfRanges >= 3,
                      let r1 = Range(m.range(at: 1), in: html),
                      let r2 = Range(m.range(at: 2), in: html),
                      let off = Int(html[r2]) else { return }
                varToOffsetNoLen[String(html[r1])] = off
            }
        }

        func firstVarOffset(_ pattern: String, in map: [String: Int], exclude: Set<Int> = []) -> Int? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for m in matches {
                guard let r = Range(m.range(at: 1), in: html) else { continue }
                let v = String(html[r])
                if let off = map[v], !exclude.contains(off) { return off }
            }
            return nil
        }

        let chOffset  = firstVarOffset(#"(\w+)==ch"#, in: varToOffset) ?? 44
        let srvOff    = firstVarOffset(#"\w+\((\w+),\s*0\s*,\s*1\)"#, in: varToOffset,
                                       exclude: [chOffset]) ?? 40
        let czStart   = firstVarOffset(#"\w+\((\w+),mm\([^)]*\),3\)"#, in: varToOffsetNoLen) ?? 0
        let pagesOff  = firstVarOffset(#"\bps=(\w+)\b"#, in: varToOffset,
                                       exclude: [chOffset, srvOff]) ?? 42

        print("[8comic] offsets: ch=\(chOffset) srv=\(srvOff) pages=\(pagesOff) cz=\(czStart)")

        // 7. 找到對應的章節記錄（每條 47 字元）
        let recordLen = 47
        var urls: [URL] = []

        var idx = yy.startIndex
        var i = 0
        while yy.distance(from: idx, to: yy.endIndex) >= recordLen {
            let blockEnd = yy.index(idx, offsetBy: recordLen)
            let block = yy[idx..<blockEnd]

            let wpStart = yy.index(idx, offsetBy: chOffset)
            let wpEnd   = yy.index(idx, offsetBy: chOffset + 2)
            let ltStart = yy.index(idx, offsetBy: 46)
            let ltEnd   = yy.index(idx, offsetBy: 47)

            if let chNum = lc(block[wpStart..<wpEnd]), chNum == ch {
                let czEnd   = yy.index(idx, offsetBy: czStart + 40)
                let qnStart = yy.index(idx, offsetBy: srvOff)
                let qnEnd   = yy.index(idx, offsetBy: srvOff + 2)
                let pbStart = yy.index(idx, offsetBy: pagesOff)
                let pbEnd   = yy.index(idx, offsetBy: pagesOff + 2)

                let cz = String(block[yy.index(idx, offsetBy: czStart)..<czEnd])
                guard let qnLc = lc(block[qnStart..<qnEnd]),
                      let pageCount = lc(block[pbStart..<pbEnd]) else { break }

                let qnStr = String(qnLc)
                let ltChar = String(block[ltStart..<ltEnd])
                let part = (ltChar == "0") ? "" : ltChar

                // domain: img{qnStr[0]}.8comic.com  subdir: qnStr[1]
                let q0 = qnStr.isEmpty ? "1" : String(qnStr[qnStr.startIndex])
                let q1 = qnStr.count > 1 ? String(qnStr[qnStr.index(qnStr.startIndex, offsetBy: 1)]) : "0"
                let domain = "\(t4)\(q0).8\(t3)\(t2)\(t3)"  // imgX.8comic.com
                let subdir = q1

                for pg in 1...max(1, pageCount) {
                    let mVal = mm(pg)
                    guard mVal + 3 <= cz.count else { break }
                    let codeStart = cz.index(cz.startIndex, offsetBy: mVal)
                    let codeEnd   = cz.index(codeStart, offsetBy: 3)
                    let code = String(cz[codeStart..<codeEnd])
                    let urlStr = "https://\(domain)/\(subdir)/\(ti)/\(ch)\(part)/\(nn(pg))_\(code).\(t1)"
                    if let u = URL(string: urlStr) { urls.append(u) }
                }
                break
            }
            idx = blockEnd
            i += 1
        }

        if urls.isEmpty {
            print("[8comic] FAIL step6: no urls generated (ch=\(ch), yy.len=\(yy.count), recordCount=\(i))")
            throw ComicServiceError.parseError
        }
        return urls
    }

    // MARK: - Gallery Detail

    func fetchGalleryDetail(galleryURL: URL) async -> GalleryDetail? {
        guard let html = try? await fetchHTML(url: galleryURL) else { return nil }
        return parseGalleryDetail(from: html)
    }

    func parseGalleryDetail(from html: String) -> GalleryDetail? {
        // <span class="mr-1 item-info-author mb-1">作者: NAME</span>
        // 或 <meta name="author" content="NAME" />
        var author: String? = nil
        if let m = html.range(of: #"item-info-author[^>]*>作者:\s*([^<]+)<"#,
                              options: .regularExpression) {
            let raw = String(html[m])
            if let inner = raw.range(of: #"作者:\s*([^<]+)"#, options: .regularExpression) {
                author = String(raw[inner])
                    .replacingOccurrences(of: #"作者:\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .htmlDecoded()
            }
        }
        if author == nil || author!.isEmpty {
            if let m = html.range(of: #"<meta name="author" content="([^"]+)""#,
                                  options: .regularExpression) {
                let raw = String(html[m])
                if let c = raw.range(of: #"content="([^"]+)""#, options: .regularExpression) {
                    author = String(raw[c])
                        .replacingOccurrences(of: #"content="|""#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .htmlDecoded()
                }
            }
        }
        guard let a = author, !a.isEmpty else { return nil }
        return GalleryDetail(author: a, description: nil)
    }

    // 向後相容 typealias
    typealias EC8Error = ComicServiceError
}
