import XCTest
@testable import ComicLib

final class ChapterNavigationTests: XCTestCase {

    private func ch(_ id: String, _ title: String) -> Chapter {
        Chapter(id: id, title: title, url: URL(string: "https://example.com/\(id)")!, pageCount: nil)
    }

    // MARK: - chapterNumber

    func test_chapterNumber_basicFormats() {
        let cases: [(String, Double, String)] = [
            ("第105話",    105,   "話"),
            ("第106集",    106,   "集"),
            ("105.5回",    105.5, "回"),
            ("第1卷",        1,   "卷"),
            ("106",         106,  ""),
            ("第105話 完", 105,   "話"),
            ("第10章",      10,   "章"),
        ]
        for (title, expectedNum, expectedSuffix) in cases {
            let result = ch("x", title).chapterNumber
            XCTAssertNotNil(result, "應能解析：\(title)")
            XCTAssertEqual(result?.0, expectedNum,     "數字錯誤：\(title)")
            XCTAssertEqual(result?.1, expectedSuffix,  "後綴錯誤：\(title)")
        }
    }

    func test_chapterNumber_returnsNilForNoNumber() {
        XCTAssertNil(ch("x", "番外篇").chapterNumber)
        XCTAssertNil(ch("x", "序章").chapterNumber)
    }

    // MARK: - adjacentChapter(after:)

    func test_adjacentAfter_basicSequence() {
        let list = [ch("1","第1話"), ch("2","第2話"), ch("3","第3話")]
        XCTAssertEqual(list.adjacentChapter(after: list[1])?.id, "3")
    }

    func test_adjacentAfter_findsNextNumber() {
        let list = [ch("100","第100話"), ch("105","第105話"), ch("106","第106話"), ch("200","第200話")]
        XCTAssertEqual(list.adjacentChapter(after: list[1])?.id, "106")
    }

    func test_adjacentAfter_multipleWithSameNumber_prefersSameSuffix() {
        let list = [ch("105","第105集"), ch("106a","第106集"), ch("106b","第106回")]
        XCTAssertEqual(list.adjacentChapter(after: list[0])?.id, "106a")
    }

    func test_adjacentAfter_multipleWithSameNumber_noMatchSuffix_picksFirst() {
        let list = [ch("105","第105話"), ch("106a","第106集"), ch("106b","第106回")]
        XCTAssertEqual(list.adjacentChapter(after: list[0])?.id, "106a")
    }

    func test_adjacentAfter_returnsNilAtEnd() {
        let list = [ch("1","第1話"), ch("2","第2話")]
        XCTAssertNil(list.adjacentChapter(after: list[1]))
    }

    // MARK: - adjacentChapter(before:)

    func test_adjacentBefore_basicSequence() {
        let list = [ch("1","第1話"), ch("2","第2話"), ch("3","第3話")]
        XCTAssertEqual(list.adjacentChapter(before: list[1])?.id, "1")
    }

    func test_adjacentBefore_findsClosestLowerNumber() {
        let list = [ch("100","第100話"), ch("105","第105話"), ch("106","第106話")]
        XCTAssertEqual(list.adjacentChapter(before: list[2])?.id, "105")
    }

    func test_adjacentBefore_returnsNilAtStart() {
        let list = [ch("1","第1話"), ch("2","第2話")]
        XCTAssertNil(list.adjacentChapter(before: list[0]))
    }
}
