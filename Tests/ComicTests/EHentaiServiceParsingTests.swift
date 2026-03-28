import XCTest
@testable import ComicLib

final class EHentaiServiceParsingTests: XCTestCase {

    let svc = EHentaiService()

    // MARK: - matches

    func test_matches_returnsAllOccurrences() {
        let html = "abc123def456"
        let result = svc.matches(pattern: #"\d+"#, in: html)
        XCTAssertEqual(result, ["123", "456"])
    }

    func test_matches_invalidPattern_returnsEmpty() {
        let result = svc.matches(pattern: "[invalid", in: "abc")
        XCTAssertEqual(result, [])
    }

    func test_matches_noMatch_returnsEmpty() {
        let result = svc.matches(pattern: #"\d+"#, in: "abc")
        XCTAssertEqual(result, [])
    }

    // MARK: - capture

    func test_capture_singleGroup() {
        let html = #"<h1 id="gn">My Gallery</h1>"#
        let result = svc.capture(pattern: #"<h1 id="gn">([^<]+)</h1>"#, in: html, group: 1)
        XCTAssertEqual(result, ["My Gallery"])
    }

    func test_capture_multipleMatches() {
        let html = "foo=1 foo=2 foo=3"
        let result = svc.capture(pattern: #"foo=(\d)"#, in: html, group: 1)
        XCTAssertEqual(result, ["1", "2", "3"])
    }

    func test_capture_noMatch_returnsEmpty() {
        let result = svc.capture(pattern: #"foo=(\d)"#, in: "no match here", group: 1)
        XCTAssertEqual(result, [])
    }

    // MARK: - captureMultiple

    func test_captureMultiple_twoGroups() {
        let html = #"href="https://e-hentai.org/g/123456/abcdef01/""#
        let result = svc.captureMultiple(
            pattern: #"href="https://e-hentai\.org/g/(\d+)/([a-f0-9]+)/""#,
            in: html, groups: [1, 2])
        XCTAssertEqual(result, [["123456", "abcdef01"]])
    }

    func test_captureMultiple_multipleEntries() {
        let html = #"href="https://e-hentai.org/g/111/aaa111/" href="https://e-hentai.org/g/222/bbb222/""#
        let result = svc.captureMultiple(
            pattern: #"href="https://e-hentai\.org/g/(\d+)/([a-f0-9]+)/""#,
            in: html, groups: [1, 2])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ["111", "aaa111"])
        XCTAssertEqual(result[1], ["222", "bbb222"])
    }

    // MARK: - parseGalleryTitle

    func test_parseGalleryTitle_gn() {
        let html = #"<h1 id="gn">Test Gallery Title</h1>"#
        XCTAssertEqual(svc.parseGalleryTitle(from: html), "Test Gallery Title")
    }

    func test_parseGalleryTitle_gj_fallback() {
        let html = #"<h1 id="gj">Japanese Title</h1>"#
        XCTAssertEqual(svc.parseGalleryTitle(from: html), "Japanese Title")
    }

    func test_parseGalleryTitle_noMatch_returnsNil() {
        XCTAssertNil(svc.parseGalleryTitle(from: "<html></html>"))
    }

    // MARK: - parseTotalResults

    func test_parseTotalResults_withCommas() {
        let html = "Showing 1,234,567 results"
        XCTAssertEqual(svc.parseTotalResults(from: html), 1234567)
    }

    func test_parseTotalResults_small() {
        let html = "42 result"
        XCTAssertEqual(svc.parseTotalResults(from: html), 42)
    }

    func test_parseTotalResults_noMatch_returnsNil() {
        XCTAssertNil(svc.parseTotalResults(from: "<html></html>"))
    }

    // MARK: - parseImagePageURLs

    func test_parseImagePageURLs_extractsURLs() {
        let html = """
        <a href="https://e-hentai.org/s/abc123def456/12345-1">page1</a>
        <a href="https://e-hentai.org/s/000fffaabb99/12345-2">page2</a>
        """
        let result = svc.parseImagePageURLs(from: html)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].contains("/s/abc123def456/12345-1"))
        XCTAssertTrue(result[1].contains("/s/000fffaabb99/12345-2"))
    }

    func test_parseImagePageURLs_duplicates_notDeduped() {
        // parseImagePageURLs 本身不去重；去重由上層 fetchImagePageURLs 的 uniqued() 負責
        let url = "https://e-hentai.org/s/abc123def456/12345-1"
        let html = "\(url) \(url)"
        let result = svc.parseImagePageURLs(from: html)
        XCTAssertEqual(result.count, 2)
    }

    func test_parseImagePageURLs_empty() {
        XCTAssertEqual(svc.parseImagePageURLs(from: "<html></html>"), [])
    }

    // MARK: - parseNextGalleryPage

    func test_parseNextGalleryPage_extractsURL() {
        let html = #"<a href="https://e-hentai.org/g/123/abc/?p=2">&gt;<"#
        let result = svc.parseNextGalleryPage(from: html)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://e-hentai.org/g/123/abc/?p=2")
    }

    func test_parseNextGalleryPage_noNext_returnsNil() {
        XCTAssertNil(svc.parseNextGalleryPage(from: "<html></html>"))
    }

    // MARK: - parseImageURL

    func test_parseImageURL_standardFormat() {
        let html = #"<img id="img" src="https://img.e-hentai.org/images/000/01/image.jpg" alt="image">"#
        let result = svc.parseImageURL(from: html)
        XCTAssertEqual(result, "https://img.e-hentai.org/images/000/01/image.jpg")
    }

    func test_parseImageURL_attributeOrderVariant() {
        let html = #"<img alt="image" id="img" src="https://img.e-hentai.org/alt.jpg">"#
        let result = svc.parseImageURL(from: html)
        XCTAssertEqual(result, "https://img.e-hentai.org/alt.jpg")
    }

    func test_parseImageURL_noMatch_returnsNil() {
        XCTAssertNil(svc.parseImageURL(from: "<html></html>"))
    }

    // MARK: - parseGalleryList

    func test_parseGalleryList_extractsGalleries() {
        let html = """
        <a href="https://e-hentai.org/g/123456/abcdef01/"><div class="glink">Gallery One</div></a>
        <a href="https://e-hentai.org/g/789012/cafebabe/"><div class="glink">Gallery Two</div></a>
        """
        let galleries = svc.parseGalleryList(from: html)
        XCTAssertEqual(galleries.count, 2)
        XCTAssertEqual(galleries[0].id, "123456")
        XCTAssertEqual(galleries[0].token, "abcdef01")
        XCTAssertEqual(galleries[0].title, "Gallery One")
        XCTAssertEqual(galleries[1].id, "789012")
        XCTAssertEqual(galleries[1].title, "Gallery Two")
    }

    func test_parseGalleryList_empty() {
        XCTAssertEqual(svc.parseGalleryList(from: "<html></html>").count, 0)
    }
}
