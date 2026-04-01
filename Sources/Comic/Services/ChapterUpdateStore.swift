import Foundation
import os.log

/// 追蹤書籤漫畫是否有比上次閱讀更新的章節
@MainActor
final class ChapterUpdateStore: ObservableObject {
    static let shared = ChapterUpdateStore()
    private let log = Logger(subsystem: "com.chenpc.comic", category: "ChapterUpdateStore")

    /// galleryID → 未讀新章節數（0 = 無更新）
    @Published private(set) var newChapterCounts: [String: Int] = [:]

    /// 所有書籤中有新章節的漫畫總數
    var totalNewCount: Int { newChapterCounts.values.filter { $0 > 0 }.count }

    // MARK: - 計算新章節

    /// 比對最新章節列表與上次閱讀位置，更新 newChapterCounts
    func update(galleryID: String, chapters: [Chapter], lastRead: ReadingProgress?) {
        guard !chapters.isEmpty else {
            newChapterCounts[galleryID] = 0; return
        }
        guard let lastRead else {
            // 從未閱讀，不顯示更新提示
            newChapterCounts[galleryID] = 0; return
        }

        guard let idx = chapters.firstIndex(where: { $0.id == lastRead.chapterID }) else {
            // 上次讀的章節找不到了（可能被刪除或重新編號）
            log.debug("update: chapterID \(lastRead.chapterID) not found in \(galleryID)")
            newChapterCounts[galleryID] = 1
            return
        }

        // 優先使用章節編號比較（最準確）
        if let lastNum = chapters[idx].chapterNumber?.0 {
            let newerCount = chapters.filter {
                ($0.chapterNumber?.0 ?? -1) > lastNum
            }.count
            newChapterCounts[galleryID] = newerCount
            log.debug("update \(galleryID): lastNum=\(lastNum), newer=\(newerCount)")
            return
        }

        // 回退：假設列表為最新在前（最常見）
        // idx > 0 代表前面有更新的章節
        newChapterCounts[galleryID] = idx
        log.debug("update \(galleryID): idx=\(idx), newer=\(idx) (newest-first fallback)")
    }

    /// 使用者開啟章節列表時呼叫，清除更新標記
    func markSeen(galleryID: String) {
        guard (newChapterCounts[galleryID] ?? 0) > 0 else { return }
        newChapterCounts[galleryID] = 0
        log.info("markSeen: \(galleryID)")
    }
}
