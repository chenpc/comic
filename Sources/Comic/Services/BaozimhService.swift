import Foundation

// 包子漫畫 (baozimh.com) — AMP SSR 頁面解析
final class BaozimhService: ComicService {
    static let shared = BaozimhService()
    private init() {}

    let session: URLSession = URLSession(configuration: .default)
    let referer = "https://www.baozimh.com"
    private let base = "https://www.baozimh.com"

    // MARK: - 列表 / 搜尋

    /// region: "" 全部, "japan" 日漫, "cn" 中國, "kr" 韓漫
    /// status: "" 全部, "serial" 連載, "pub" 完結
    /// sort:   "0" 人氣, "1" 更新
    func fetchList(page: Int, search: String, region: String, status: String, sort: String) async throws -> (galleries: [Gallery], totalPages: Int) {
        let url: URL
        if search.isEmpty {
            var comps = URLComponents(string: "\(base)/classify")!
            comps.queryItems = [
                .init(name: "type",   value: "0"),
                .init(name: "region", value: region),
                .init(name: "state",  value: status),
                .init(name: "sort",   value: sort),
                .init(name: "page",   value: "\(page)"),
            ]
            url = comps.url!
        } else {
            var comps = URLComponents(string: "\(base)/search")!
            comps.queryItems = [
                .init(name: "q",    value: search),
                .init(name: "page", value: "\(page)"),
            ]
            url = comps.url!
        }
        let html = try await fetchHTML(url: url)
        let galleries = parseGalleryList(html: html)
        let totalPages = parseTotalPages(html: html)
        return (galleries, totalPages)
    }

    // MARK: - 章節列表

    func fetchChapters(galleryURL: URL) async throws -> [Chapter] {
        let html = try await fetchHTML(url: galleryURL)
        return parseChapters(html: html, slug: galleryURL.lastPathComponent)
    }

    // MARK: - 漫畫詳細

    func fetchGalleryDetail(galleryURL: URL) async throws -> GalleryDetail {
        let html = try await fetchHTML(url: galleryURL)
        return parseGalleryDetail(html: html)
    }

    // MARK: - 章節圖片

    func fetchImageURLs(chapterURL: URL) async throws -> [URL] {
        let html = try await fetchHTML(url: chapterURL)
        return parseImageURLs(html: html)
    }

    // MARK: - 解析：漫畫列表

    func parseGalleryList(html: String) -> [Gallery] {
        // 抓 href="/comic/{slug}" 和對應 amp-img src + h3 標題
        // 每張卡片格式：
        //   <a href="/comic/{slug}" class="comics-card__poster ...">
        //     <amp-img src="https://static-tw.baozimh.com/cover/{slug}.jpg...">
        //   ...
        //   <a href="/comic/{slug}" class="comics-card__info">
        //     <h3 ...>{title}</h3>
        let cardPattern = #"href="/comic/([^"]+)"[^>]*class="comics-card__poster[^"]*"[^>]*>.*?<amp-img[^>]+src="([^"]+)".*?<h3[^>]*>([^<]+)</h3>"#
        guard let regex = try? NSRegularExpression(pattern: cardPattern, options: .dotMatchesLineSeparators) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var galleries: [Gallery] = []
        for m in regex.matches(in: html, range: range) {
            guard let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html),
                  let r3 = Range(m.range(at: 3), in: html) else { continue }
            let slug  = String(html[r1])
            let thumb = URL(string: String(html[r2]))
            let title = String(html[r3]).trimmingCharacters(in: .whitespacesAndNewlines)
            let galleryURL = URL(string: "\(base)/comic/\(slug)")!
            galleries.append(Gallery(id: slug, token: slug, title: title,
                                     thumbURL: thumb, pageCount: nil, category: nil,
                                     uploader: nil, source: SourceID.baozimh.rawValue,
                                     galleryURL: galleryURL))
        }
        return galleries
    }

    // MARK: - 解析：總頁數

    func parseTotalPages(html: String) -> Int {
        // <a ...?page=N...> 找最大頁數
        let pattern = #"\?[^"]*page=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 1 }
        let range = NSRange(html.startIndex..., in: html)
        var maxPage = 1
        for m in regex.matches(in: html, range: range) {
            if let r = Range(m.range(at: 1), in: html),
               let n = Int(html[r]) {
                maxPage = max(maxPage, n)
            }
        }
        return maxPage
    }

    // MARK: - 解析：章節列表

    func parseChapters(html: String, slug: String) -> [Chapter] {
        // 章節連結格式：href="/user/page_direct?comic_id={slug}&section_slot=0&chapter_slot={N}"
        // 標題在 <span>{title}</span> 內
        let pattern = #"chapter_slot=(\d+)"[^>]*>\s*<div[^>]*>\s*<span>([^<]+)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var chapters: [Chapter] = []
        for m in regex.matches(in: html, range: range) {
            guard let r1 = Range(m.range(at: 1), in: html),
                  let r2 = Range(m.range(at: 2), in: html) else { continue }
            let slot  = String(html[r1])
            let title = String(html[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
            let chURL = URL(string: "\(base)/comic/chapter/\(slug)/0_\(slot).html")!
            chapters.append(Chapter(id: "\(slug)/0_\(slot)", title: title, url: chURL, pageCount: nil))
        }
        return chapters
    }

    // MARK: - 解析：漫畫詳細

    func parseGalleryDetail(html: String) -> GalleryDetail {
        let author = metaContent(html: html, name: "og:novel:author")
        let desc   = metaContent(html: html, name: "description")
        let status = metaContent(html: html, name: "og:novel:status")
        return GalleryDetail(author: author, description: desc, status: status)
    }

    private func metaContent(html: String, name: String) -> String? {
        let pattern = #"name="\#(NSRegularExpression.escapedPattern(for: name))"[^>]+content="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 解析：章節圖片

    func parseImageURLs(html: String) -> [URL] {
        // 每張圖片：<script type="application/json">{"url": "https://...jpg"}</script>
        let pattern = #"\{"url":\s*"(https://[^"]+)"\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            return URL(string: String(html[r]))
        }
    }
}
