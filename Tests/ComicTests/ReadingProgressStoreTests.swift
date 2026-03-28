import XCTest
@testable import ComicLib

// MARK: - ReadingProgress Codable 向後相容

final class ReadingProgressCodableTests: XCTestCase {

    func test_decode_withoutPageIndex_defaultsToZero() throws {
        // 舊格式 JSON 不含 pageIndex
        let json = """
        {
          "galleryID": "g1",
          "chapterID": "c1",
          "chapterTitle": "第01集",
          "chapterURL": "https://example.com/ch1",
          "lastReadAt": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let progress = try decoder.decode(ReadingProgress.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(progress.pageIndex, 0, "舊資料缺少 pageIndex 應預設為 0")
    }

    func test_decode_withPageIndex_usesStoredValue() throws {
        let json = """
        {
          "galleryID": "g1",
          "chapterID": "c1",
          "chapterTitle": "第01集",
          "chapterURL": "https://example.com/ch1",
          "pageIndex": 42,
          "lastReadAt": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let progress = try decoder.decode(ReadingProgress.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(progress.pageIndex, 42)
    }

    func test_roundtrip_preservesAllFields() throws {
        let original = ReadingProgress(
            galleryID: "g1",
            chapterID: "ch1",
            chapterTitle: "第01集",
            chapterURL: URL(string: "https://example.com/ch1")!,
            pageIndex: 7,
            lastReadAt: Date(timeIntervalSince1970: 1000))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(ReadingProgress.self, from: data)

        XCTAssertEqual(decoded.galleryID, "g1")
        XCTAssertEqual(decoded.chapterID, "ch1")
        XCTAssertEqual(decoded.chapterTitle, "第01集")
        XCTAssertEqual(decoded.pageIndex, 7)
        XCTAssertEqual(decoded.chapterURL.absoluteString, "https://example.com/ch1")
    }
}

// MARK: - ReadingProgressStore 邏輯測試

@MainActor
final class ReadingProgressStoreTests: XCTestCase {

    var store: ReadingProgressStore!

    override func setUp() async throws {
        store = ReadingProgressStore()
    }

    func test_lastRead_initiallyNil() {
        XCTAssertNil(store.lastRead(galleryID: "nonexistent"))
    }

    func test_record_then_lastRead_returnsProgress() {
        let gallery = makeGallery(id: "g1")
        let chapter = makeChapter(id: "c1", title: "第01集", urlStr: "https://example.com/c1")
        store.record(gallery: gallery, chapter: chapter, pageIndex: 5)
        let p = store.lastRead(galleryID: "g1")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.chapterID, "c1")
        XCTAssertEqual(p?.pageIndex, 5)
    }

    func test_record_overwrites_previousProgress() {
        let gallery = makeGallery(id: "g2")
        let ch1 = makeChapter(id: "c1", title: "第01集", urlStr: "https://example.com/c1")
        let ch2 = makeChapter(id: "c2", title: "第02集", urlStr: "https://example.com/c2")
        store.record(gallery: gallery, chapter: ch1, pageIndex: 3)
        store.record(gallery: gallery, chapter: ch2, pageIndex: 7)
        let p = store.lastRead(galleryID: "g2")
        XCTAssertEqual(p?.chapterID, "c2", "新紀錄應覆蓋舊紀錄")
        XCTAssertEqual(p?.pageIndex, 7)
    }

    func test_clear_removesProgress() {
        let gallery = makeGallery(id: "g3")
        let chapter = makeChapter(id: "c1", title: "第01集", urlStr: "https://example.com/c1")
        store.record(gallery: gallery, chapter: chapter, pageIndex: 0)
        store.clear(galleryID: "g3")
        XCTAssertNil(store.lastRead(galleryID: "g3"))
    }

    func test_record_defaultPageIndex_isZero() {
        let gallery = makeGallery(id: "g4")
        let chapter = makeChapter(id: "c1", title: "第01集", urlStr: "https://example.com/c1")
        store.record(gallery: gallery, chapter: chapter)
        XCTAssertEqual(store.lastRead(galleryID: "g4")?.pageIndex, 0)
    }

    // MARK: - Helpers

    private func makeGallery(id: String) -> Gallery {
        Gallery(id: id, token: "tok", title: "Gallery \(id)",
                thumbURL: nil, pageCount: nil, category: nil, uploader: nil)
    }

    private func makeChapter(id: String, title: String, urlStr: String) -> Chapter {
        Chapter(id: id, title: title, url: URL(string: urlStr)!, pageCount: nil)
    }
}
