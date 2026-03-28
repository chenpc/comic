import XCTest
@testable import ComicLib

@MainActor
final class DownloadManagerPureTests: XCTestCase {

    var dm: DownloadManager!

    override func setUp() async throws {
        dm = DownloadManager()
    }

    // MARK: - safeFilename

    func test_safeFilename_stripsForwardSlash() {
        XCTAssertEqual(dm.safeFilename("a/b"), "a_b")
    }

    func test_safeFilename_stripsBackslash() {
        XCTAssertEqual(dm.safeFilename("a\\b"), "a_b")
    }

    func test_safeFilename_stripsColon() {
        XCTAssertEqual(dm.safeFilename("a:b"), "a_b")
    }

    func test_safeFilename_stripsMultipleInvalidChars() {
        XCTAssertEqual(dm.safeFilename("a/b\\c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j")
    }

    func test_safeFilename_noInvalidChars_unchanged() {
        XCTAssertEqual(dm.safeFilename("Chapter 01"), "Chapter 01")
    }

    func test_safeFilename_emptyString() {
        XCTAssertEqual(dm.safeFilename(""), "")
    }

    func test_safeFilename_unicodeUnchanged() {
        XCTAssertEqual(dm.safeFilename("第01集"), "第01集")
    }

    // MARK: - imageFile

    func test_imageFile_zeroIndex_formatsCorrectly() {
        let dir = URL(fileURLWithPath: "/tmp/staging")
        let result = dm.imageFile(stagingDir: dir, index: 0, ext: "jpg")
        XCTAssertEqual(result.lastPathComponent, "0001.jpg")
    }

    func test_imageFile_index9_pads() {
        let dir = URL(fileURLWithPath: "/tmp/staging")
        let result = dm.imageFile(stagingDir: dir, index: 9, ext: "png")
        XCTAssertEqual(result.lastPathComponent, "0010.png")
    }

    func test_imageFile_largeIndex() {
        let dir = URL(fileURLWithPath: "/tmp/staging")
        let result = dm.imageFile(stagingDir: dir, index: 999, ext: "webp")
        XCTAssertEqual(result.lastPathComponent, "1000.webp")
    }

    func test_imageFile_pathIncludesStagingDir() {
        let dir = URL(fileURLWithPath: "/tmp/myfolder")
        let result = dm.imageFile(stagingDir: dir, index: 0, ext: "jpg")
        XCTAssertTrue(result.path.hasPrefix("/tmp/myfolder/"))
    }

    // MARK: - DownloadProgress.isFinished

    func test_downloadProgress_isFinished_whenAllComplete() {
        let p = DownloadProgress(
            galleryID: "1", galleryTitle: "T", galleryToken: "tok",
            pageURLs: ["a", "b", "c"], completedIndices: [0, 1, 2])
        XCTAssertTrue(p.isFinished)
    }

    func test_downloadProgress_isFinished_partiallyComplete() {
        let p = DownloadProgress(
            galleryID: "1", galleryTitle: "T", galleryToken: "tok",
            pageURLs: ["a", "b", "c"], completedIndices: [0, 1])
        XCTAssertFalse(p.isFinished)
    }

    func test_downloadProgress_isFinished_emptyPages() {
        let p = DownloadProgress(
            galleryID: "1", galleryTitle: "T", galleryToken: "tok",
            pageURLs: [], completedIndices: [])
        XCTAssertFalse(p.isFinished)
    }

    // MARK: - DownloadState.progress

    func test_downloadState_progress_downloading() {
        let state = DownloadManager.DownloadState.downloading(page: 3, total: 10)
        XCTAssertEqual(state.progress, 0.3, accuracy: 0.001)
    }

    func test_downloadState_progress_downloading_zeroTotal() {
        let state = DownloadManager.DownloadState.downloading(page: 0, total: 0)
        XCTAssertEqual(state.progress, 0.0)
    }

    func test_downloadState_progress_packaging() {
        XCTAssertEqual(DownloadManager.DownloadState.packaging.progress, 1.0)
    }

    func test_downloadState_progress_completed() {
        XCTAssertEqual(DownloadManager.DownloadState.completed.progress, 1.0)
    }

    func test_downloadState_progress_notDownloaded() {
        XCTAssertEqual(DownloadManager.DownloadState.notDownloaded.progress, 0.0)
    }

    func test_downloadState_progress_queued() {
        XCTAssertEqual(DownloadManager.DownloadState.queued.progress, 0.0)
    }

    // MARK: - DownloadState.isActive

    func test_downloadState_isActive_queued() {
        XCTAssertTrue(DownloadManager.DownloadState.queued.isActive)
    }

    func test_downloadState_isActive_downloading() {
        XCTAssertTrue(DownloadManager.DownloadState.downloading(page: 1, total: 5).isActive)
    }

    func test_downloadState_isActive_packaging() {
        XCTAssertTrue(DownloadManager.DownloadState.packaging.isActive)
    }

    func test_downloadState_isActive_notDownloaded() {
        XCTAssertFalse(DownloadManager.DownloadState.notDownloaded.isActive)
    }

    func test_downloadState_isActive_completed() {
        XCTAssertFalse(DownloadManager.DownloadState.completed.isActive)
    }

    func test_downloadState_isActive_failed() {
        XCTAssertFalse(DownloadManager.DownloadState.failed("error").isActive)
    }
}
