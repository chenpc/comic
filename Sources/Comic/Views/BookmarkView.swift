import SwiftUI

struct BookmarkView: View {
    @ObservedObject var store: BookmarkStore
    let onSelect: (Gallery) -> Void

    @ObservedObject private var sourceMgr  = SourceManager.shared
    @ObservedObject private var updateStore = ChapterUpdateStore.shared
    @ObservedObject private var progressStore = ReadingProgressStore.shared
    @State private var isRefreshing = false
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]

    private var filtered: [Gallery] {
        store.bookmarks.filter { $0.sourceID == sourceMgr.activeSourceID }
    }

    var body: some View {
        if filtered.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                Text("尚無書籤")
                    .foregroundColor(.secondary)
                Text("在圖庫卡片上點擊 ★ 加入書籤")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // 更新提示 banner
                let newCount = filtered.filter { (updateStore.newChapterCounts[$0.id] ?? 0) > 0 }.count
                if newCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.orange)
                        Text("\(newCount) 部漫畫有新章節")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if isRefreshing {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    Divider()
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { gallery in
                            BookmarkCard(gallery: gallery, onSelect: onSelect, store: store)
                        }
                    }
                    .padding(10)
                }
            }
            .task(id: sourceMgr.activeSourceID) { await refreshAll() }
            .onChange(of: store.bookmarks.count) { _, _ in
                Task { await refreshAll() }
            }
        }
    }

    // MARK: - 後台刷新章節更新狀態

    private func refreshAll() async {
        let galleries = filtered.filter {
            SourceManager.shared.source(for: $0.sourceID).hasChapters
        }
        guard !galleries.isEmpty else { return }
        isRefreshing = true
        await withTaskGroup(of: Void.self) { group in
            for gallery in galleries {
                group.addTask { await refreshOne(gallery) }
            }
        }
        isRefreshing = false
    }

    private func refreshOne(_ gallery: Gallery) async {
        let source = SourceManager.shared.source(for: gallery.sourceID)
        guard let chapters = try? await source.fetchChapters(gallery: gallery) else { return }
        let lastRead = progressStore.lastRead(galleryID: gallery.id)
        await MainActor.run {
            updateStore.update(galleryID: gallery.id, chapters: chapters, lastRead: lastRead)
        }
    }
}

// MARK: - 書籤卡片（含下載狀態）

struct BookmarkCard: View {
    let gallery: Gallery
    let onSelect: (Gallery) -> Void
    let store: BookmarkStore
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var updateStore = ChapterUpdateStore.shared

    private var newCount: Int { updateStore.newChapterCounts[gallery.id] ?? 0 }

    var body: some View {
        let dlState = downloads.state(for: gallery)

        ZStack(alignment: .topTrailing) {
            Button { onSelect(gallery) } label: {
                GalleryCard(gallery: gallery)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 右上角：書籤移除
            Button {
                store.toggle(gallery)
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.yellow)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)

            // 左上角：下載狀態
            downloadBadge(state: dlState)

            // 底部：新章節提示條
            if newCount > 0 {
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 10))
                        Text(newCount == 1 ? "有新章節" : "新 \(newCount) 章")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                }
                .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
                .allowsHitTesting(false)
            }
        }
        // 下載進度條（疊在卡片底部）
        .overlay(alignment: .bottom) {
            if case .downloading(let p, let t) = dlState, t > 0 {
                ProgressView(value: Double(p), total: Double(t))
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 52)
            }
        }
    }

    @ViewBuilder
    private func downloadBadge(state: DownloadManager.DownloadState) -> some View {
        Group {
            switch state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())

            case .downloading(let p, let t):
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    Circle()
                        .trim(from: 0, to: t > 0 ? Double(p) / Double(t) : 0)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                        .foregroundColor(.accentColor)
                }
                .padding(4)
                .background(.ultraThinMaterial)
                .clipShape(Circle())

            case .packaging:
                ProgressView()
                    .scaleEffect(0.6)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())

            case .failed:
                Button {
                    downloads.download(gallery: gallery)
                } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

            case .notDownloaded, .queued:
                if settings.libraryURL != nil && state != .queued {
                    Button {
                        downloads.download(gallery: gallery)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.white)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else if state == .queued {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.leading, 6)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
