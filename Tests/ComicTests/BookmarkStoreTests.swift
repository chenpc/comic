import XCTest
@testable import ComicLib

@MainActor
final class BookmarkStoreTests: XCTestCase {

    // 使用獨立的 store 實例（不是 .shared，避免影響真實資料）
    var store: BookmarkStore!
    // 唯一前綴，確保 ID 不會和磁碟既有書籤衝突
    let prefix = "test-unit-\(UUID().uuidString)-"

    override func setUp() async throws {
        store = BookmarkStore()
        // 清除測試前可能殘留的 test 書籤
        let ids = store.bookmarks.filter { $0.id.hasPrefix("test-unit-") }.map { $0.id }
        for id in ids { store.toggle(makeGallery(id: id)) }
    }

    override func tearDown() async throws {
        // 清除本次加入的書籤
        if store.isBookmarked(makeGallery(id: prefix + "A")) {
            store.toggle(makeGallery(id: prefix + "A"))
        }
        if store.isBookmarked(makeGallery(id: prefix + "B")) {
            store.toggle(makeGallery(id: prefix + "B"))
        }
        if store.isBookmarked(makeGallery(id: prefix + "C")) {
            store.toggle(makeGallery(id: prefix + "C"))
        }
    }

    // MARK: - isBookmarked

    func test_isBookmarked_unknownID_false() {
        XCTAssertFalse(store.isBookmarked(makeGallery(id: prefix + "unknown")))
    }

    func test_isBookmarked_afterToggleOn_true() {
        let g = makeGallery(id: prefix + "A")
        store.toggle(g)
        XCTAssertTrue(store.isBookmarked(g))
    }

    func test_isBookmarked_afterToggleOnAndOff_false() {
        let g = makeGallery(id: prefix + "A")
        store.toggle(g)   // add
        store.toggle(g)   // remove
        XCTAssertFalse(store.isBookmarked(g))
    }

    // MARK: - toggle add behavior

    func test_toggle_add_insertsAtFront() {
        let g1 = makeGallery(id: prefix + "A")
        let g2 = makeGallery(id: prefix + "B")
        store.toggle(g1)
        store.toggle(g2)
        XCTAssertEqual(store.bookmarks.first?.id, prefix + "B", "後加的應置頂")
    }

    func test_toggle_add_increasesCount() {
        let before = store.bookmarks.count
        store.toggle(makeGallery(id: prefix + "C"))
        XCTAssertEqual(store.bookmarks.count, before + 1)
    }

    // MARK: - toggle remove behavior

    func test_toggle_remove_decreasesCount() {
        let g = makeGallery(id: prefix + "A")
        store.toggle(g)
        let after = store.bookmarks.count
        store.toggle(g)
        XCTAssertEqual(store.bookmarks.count, after - 1)
    }

    func test_toggle_remove_galleryNoLongerInList() {
        let g = makeGallery(id: prefix + "A")
        store.toggle(g)
        store.toggle(g)
        XCTAssertFalse(store.bookmarks.contains { $0.id == g.id })
    }

    // MARK: - Helpers

    private func makeGallery(id: String) -> Gallery {
        Gallery(id: id, token: "tok", title: "Gallery \(id)",
                thumbURL: nil, pageCount: nil, category: nil, uploader: nil)
    }
}
