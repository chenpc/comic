import XCTest
@testable import ComicLib

final class CloudStorageHelperTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - migrate

    func test_migrate_srcExists_movesToDst() throws {
        let src = tmpDir.appendingPathComponent("src.json")
        let dst = tmpDir.appendingPathComponent("dst.json")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let result = CloudStorageHelper.migrate(from: src, to: dst)

        XCTAssertTrue(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "src 應已被移走")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path), "dst 應存在")
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "hello")
    }

    func test_migrate_srcNotExists_returnsFalse() {
        let src = tmpDir.appendingPathComponent("nonexistent.json")
        let dst = tmpDir.appendingPathComponent("dst.json")

        let result = CloudStorageHelper.migrate(from: src, to: dst)

        XCTAssertFalse(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
    }

    func test_migrate_dstAlreadyExists_overwrite() throws {
        let src = tmpDir.appendingPathComponent("src.json")
        let dst = tmpDir.appendingPathComponent("dst.json")
        try "new".write(to: src, atomically: true, encoding: .utf8)
        try "old".write(to: dst, atomically: true, encoding: .utf8)

        let result = CloudStorageHelper.migrate(from: src, to: dst)

        XCTAssertTrue(result)
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "new", "dst 應被新內容覆蓋")
    }

    // MARK: - migrateIfNeeded

    func test_migrateIfNeeded_srcExists_dstNotExists_moves() throws {
        let src = tmpDir.appendingPathComponent("src.json")
        let dst = tmpDir.appendingPathComponent("dst.json")
        try "data".write(to: src, atomically: true, encoding: .utf8)

        let result = CloudStorageHelper.migrateIfNeeded(from: src, to: dst)

        XCTAssertTrue(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
    }

    func test_migrateIfNeeded_dstAlreadyExists_skips() throws {
        let src = tmpDir.appendingPathComponent("src.json")
        let dst = tmpDir.appendingPathComponent("dst.json")
        try "src-data".write(to: src, atomically: true, encoding: .utf8)
        try "dst-data".write(to: dst, atomically: true, encoding: .utf8)

        let result = CloudStorageHelper.migrateIfNeeded(from: src, to: dst)

        XCTAssertFalse(result, "dst 已存在不應搬移")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        XCTAssertEqual(try String(contentsOf: dst, encoding: .utf8), "dst-data", "dst 不應被覆蓋")
    }

    func test_migrateIfNeeded_srcNotExists_skips() {
        let src = tmpDir.appendingPathComponent("nonexistent.json")
        let dst = tmpDir.appendingPathComponent("dst.json")

        let result = CloudStorageHelper.migrateIfNeeded(from: src, to: dst)

        XCTAssertFalse(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))
    }

    // MARK: - localDirectory

    func test_localDirectory_exists() {
        let dir = CloudStorageHelper.localDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_localDirectory_isDirectory() {
        let dir = CloudStorageHelper.localDirectory
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - iCloudDriveDirectory

    func test_iCloudDriveDirectory_returnsNilOrValidURL() {
        let url = CloudStorageHelper.iCloudDriveDirectory()
        if let url {
            XCTAssertEqual(url.lastPathComponent, "Comic")
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            XCTAssertTrue(isDir.boolValue, "iCloud Drive Comic 目錄應為資料夾")
        }
        // nil = iCloud Drive 未啟用，也是合法結果
    }

    // MARK: - resolveCloudDirectory

    func test_resolveCloudDirectory_completionCalledOnMainThread() async {
        await withCheckedContinuation { continuation in
            CloudStorageHelper.resolveCloudDirectory { _ in
                XCTAssertTrue(Thread.isMainThread, "completion 應在 MainActor 執行")
                continuation.resume()
            }
        }
    }

    func test_resolveCloudDirectory_nilResolver_completionReceivesNil() async {
        await withCheckedContinuation { continuation in
            CloudStorageHelper.resolveCloudDirectory(resolver: { nil }) { url in
                XCTAssertNil(url, "resolver 回傳 nil 時 completion 應收到 nil")
                continuation.resume()
            }
        }
    }

    func test_resolveCloudDirectory_nilResolver_calledOnMainThread() async {
        await withCheckedContinuation { continuation in
            CloudStorageHelper.resolveCloudDirectory(resolver: { nil }) { _ in
                XCTAssertTrue(Thread.isMainThread, "即使 resolver 回傳 nil，completion 仍應在 MainActor 執行")
                continuation.resume()
            }
        }
    }

    func test_resolveCloudDirectory_validResolver_returnsURL() async {
        await withCheckedContinuation { continuation in
            CloudStorageHelper.resolveCloudDirectory(resolver: { [self] in self.tmpDir }) { url in
                XCTAssertNotNil(url, "resolver 有值時應回傳非 nil URL")
                XCTAssertEqual(url, self.tmpDir)
                continuation.resume()
            }
        }
    }
}
