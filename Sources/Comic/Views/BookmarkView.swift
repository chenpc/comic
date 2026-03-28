import SwiftUI

struct BookmarkView: View {
    @ObservedObject var store: BookmarkStore
    let onSelect: (Gallery) -> Void

    @ObservedObject private var sourceMgr = SourceManager.shared
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
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { gallery in
                        BookmarkCard(gallery: gallery, onSelect: onSelect, store: store)
                    }
                }
                .padding(10)
            }
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

    var body: some View {
        let dlState = downloads.state(for: gallery)

        ZStack(alignment: .topTrailing) {
            GalleryCard(gallery: gallery)
                .onTapGesture { onSelect(gallery) }

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
