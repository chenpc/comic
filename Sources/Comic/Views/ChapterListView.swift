import SwiftUI

struct ChapterListView: View {
    let gallery: Gallery
    let onSelect: (Chapter, [Chapter], Int) -> Void   // Chapter, allChapters, startPage
    let onBack: () -> Void

    @State private var chapters: [Chapter] = []
    @State private var isLoading = true
    @State private var error: String?
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var progressStore = ReadingProgressStore.shared

    private var lastRead: ReadingProgress? { progressStore.lastRead(galleryID: gallery.id) }

    /// 顯示用的章節順序：上次看的章節置頂，其餘維持原順序
    private var displayChapters: [Chapter] {
        guard let last = lastRead,
              let idx = chapters.firstIndex(where: { $0.url == last.chapterURL }),
              idx != 0 else { return chapters }
        var reordered = chapters
        let pinned = reordered.remove(at: idx)
        reordered.insert(pinned, at: 0)
        return reordered
    }

    private var undownloadedCount: Int {
        guard !chapters.isEmpty else { return 0 }
        let downloaded = downloads.downloadedChapterCount(gallery: gallery)
        return max(0, chapters.count - downloaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 標題列
            HStack {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                }
                .buttonStyle(.borderless)

                Spacer()
                Text(gallery.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if !isLoading, !chapters.isEmpty {
                // 繼續閱讀 Banner
                if let last = lastRead,
                   let chapter = chapters.first(where: { $0.url == last.chapterURL }) {
                    continueBanner(chapter: chapter, pageIndex: last.pageIndex)
                    Divider()
                }

                // 未下載提示
                if undownloadedCount > 0 {
                    downloadBanner
                    Divider()
                }
            }

            if isLoading {
                Spacer()
                ProgressView("載入章節中...")
                Spacer()
            } else if let error = error {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(error).foregroundColor(.secondary)
                    Button("重試") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if chapters.isEmpty {
                Spacer()
                Text("沒有找到章節").foregroundColor(.secondary)
                Spacer()
            } else {
                List(displayChapters) { chapter in
                    ChapterRow(
                        chapter: chapter,
                        gallery: gallery,
                        isLastRead: chapter.url == lastRead?.chapterURL,
                        onSelect: { onSelect(chapter, chapters, 0) }  // 從頭開始；繼續閱讀由 banner 傳 pageIndex
                    )
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Sub views

    private func continueBanner(chapter: Chapter, pageIndex: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("上次看到")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(chapter.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if pageIndex > 0 {
                        Text("第 \(pageIndex + 1) 頁")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button("繼續閱讀") {
                onSelect(chapter, chapters, pageIndex)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private var downloadBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
            Text("有 \(undownloadedCount) 集尚未下載（共 \(chapters.count) 集）")
                .font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Button("全部下載") {
                for ch in chapters { downloads.downloadChapter(chapter: ch, gallery: gallery) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.07))
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            chapters = try await ManhuaguiSource.shared.fetchChapters(gallery: gallery)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 章節列表行

private struct ChapterRow: View {
    let chapter: Chapter
    let gallery: Gallery
    let isLastRead: Bool
    let onSelect: () -> Void
    @ObservedObject private var downloads = DownloadManager.shared

    var dlState: DownloadManager.DownloadState {
        downloads.chapterState(chapter: chapter, gallery: gallery)
    }

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    // 已讀標記 or 下載完成圖示
                    if isLastRead {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                    } else if dlState == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 20)
                    } else {
                        Image(systemName: "book.pages")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }

                    Text(chapter.title)
                        .font(.system(size: 13))
                        .foregroundColor(isLastRead ? .accentColor : .primary)
                        .fontWeight(isLastRead ? .medium : .regular)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            downloadControl
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch dlState {
        case .notDownloaded:
            Button { downloads.downloadChapter(chapter: chapter, gallery: gallery) } label: {
                Image(systemName: "arrow.down.circle").foregroundColor(.secondary)
            }.buttonStyle(.plain)
        case .queued:
            Image(systemName: "clock").foregroundColor(.secondary).font(.system(size: 14))
        case .downloading(let p, let t):
            HStack(spacing: 4) {
                if t > 0 {
                    Text("\(p)/\(t)").font(.system(size: 10)).foregroundColor(.secondary)
                }
                ProgressView().scaleEffect(0.6).frame(width: 18, height: 18)
            }
        case .packaging:
            ProgressView().scaleEffect(0.6).frame(width: 18, height: 18)
        case .completed:
            EmptyView()
        case .failed:
            Button { downloads.downloadChapter(chapter: chapter, gallery: gallery) } label: {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            }.buttonStyle(.plain)
        }
    }
}
