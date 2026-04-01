import Foundation
import Testing
@testable import ComicLib

@Suite("Library search filter")
struct LibrarySearchTests {
    private static func makeGallery(id: String, title: String, source: String = "manhuagui") -> Gallery {
        Gallery(id: id, token: id, title: title, thumbURL: nil, pageCount: nil,
                category: nil, uploader: nil, source: source,
                galleryURL: URL(string: "file:///\(id)")!)
    }

    /// 搜尋篩選：與 LibraryView.filterGalleries 相同邏輯
    private static func filterGalleries(_ galleries: [Gallery], query: String) -> [Gallery] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return galleries }
        return galleries.filter { $0.title.lowercased().contains(q) }
    }

    private let galleries = [
        makeGallery(id: "1", title: "妖神記", source: "manhuaren"),
        makeGallery(id: "2", title: "一拳超人"),
        makeGallery(id: "3", title: "進擊的巨人"),
    ]

    @Test func emptyQuery_returnsAll() {
        #expect(Self.filterGalleries(galleries, query: "").count == 3)
    }

    @Test func whitespaceQuery_returnsAll() {
        #expect(Self.filterGalleries(galleries, query: "   ").count == 3)
    }

    @Test func matchesByTitle() {
        let result = Self.filterGalleries(galleries, query: "妖神")
        #expect(result.count == 1)
        #expect(result[0].title == "妖神記")
    }

    @Test func caseInsensitive() {
        let mixed = [Self.makeGallery(id: "4", title: "One Punch Man", source: "ehentai")]
        #expect(Self.filterGalleries(mixed, query: "one punch").count == 1)
    }

    @Test func noMatch_returnsEmpty() {
        #expect(Self.filterGalleries(galleries, query: "不存在的漫畫").isEmpty)
    }
}
