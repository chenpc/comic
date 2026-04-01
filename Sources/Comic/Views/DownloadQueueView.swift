import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject private var downloads = DownloadManager.shared

    // 章節任務：queued 或 downloading，依入隊順序排列
    private var activeChapterTasks: [(key: String, chapter: Chapter, gallery: Gallery, state: DownloadManager.DownloadState, order: Int)] {
        downloads.chapterMeta.compactMap { key, meta in
            let state = downloads.chapterStates[key] ?? .notDownloaded
            guard state.isActive else { return nil }
            return (key: key, chapter: meta.chapter, gallery: meta.gallery, state: state, order: meta.order)
        }
        .sorted { $0.order < $1.order }
    }

    // 圖庫任務（E-Hentai）：queued 或 downloading，依入隊順序排列
    private var activeGalleryTasks: [(gallery: Gallery, state: DownloadManager.DownloadState, order: Int)] {
        downloads.galleryMeta.compactMap { id, meta in
            let state = downloads.states[id] ?? .notDownloaded
            guard state.isActive else { return nil }
            return (gallery: meta.gallery, state: state, order: meta.order)
        }
        .sorted { $0.order < $1.order }
    }

    private var isEmpty: Bool {
        activeChapterTasks.isEmpty && activeGalleryTasks.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 標題列
            HStack {
                Text("下載佇列")
                    .font(.headline)
                Spacer()
                if !isEmpty {
                    Button("全部暫停") {
                        for task in activeChapterTasks {
                            downloads.pauseChapterDownload(chapter: task.chapter)
                        }
                        for task in activeGalleryTasks {
                            downloads.cancelDownload(gallery: task.gallery)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("沒有進行中的下載")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    // 章節任務
                    if !activeChapterTasks.isEmpty {
                        Section("章節下載") {
                            ForEach(activeChapterTasks, id: \.key) { task in
                                ChapterTaskRow(
                                    chapter: task.chapter,
                                    gallery: task.gallery,
                                    state: task.state
                                )
                            }
                        }
                    }

                    // 圖庫任務
                    if !activeGalleryTasks.isEmpty {
                        Section("圖庫下載") {
                            ForEach(activeGalleryTasks, id: \.gallery.id) { task in
                                GalleryTaskRow(gallery: task.gallery, state: task.state)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 章節任務列

private struct ChapterTaskRow: View {
    let chapter: Chapter
    let gallery: Gallery
    let state: DownloadManager.DownloadState
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            stateIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(gallery.title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(chapter.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if case .downloading(let p, let t) = state, t > 0 {
                    ProgressView(value: Double(p), total: Double(t))
                        .progressViewStyle(.linear)
                    Text("\(p) / \(t) 頁").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }

            Spacer()

            actionButtons
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .frame(width: 20)
        case .downloading:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch state {
        case .queued:
            Button {
                downloads.pauseChapterDownload(chapter: chapter)
            } label: {
                Image(systemName: "pause.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        case .downloading:
            Button {
                downloads.pauseChapterDownload(chapter: chapter)
            } label: {
                Image(systemName: "pause.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }
}

// MARK: - 圖庫任務列

private struct GalleryTaskRow: View {
    let gallery: Gallery
    let state: DownloadManager.DownloadState
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            stateIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(gallery.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if case .downloading(let p, let t) = state, t > 0 {
                    ProgressView(value: Double(p), total: Double(t))
                        .progressViewStyle(.linear)
                    Text("\(p) / \(t) 頁").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                downloads.cancelDownload(gallery: gallery)
            } label: {
                Image(systemName: "pause.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .frame(width: 20)
        case .downloading:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20)
        default:
            EmptyView()
        }
    }
}
