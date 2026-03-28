import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var progressStore = ReadingProgressStore.shared
    @State private var cacheSize: Int = 0
    @State private var showICloudHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("設定")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 4)

            // Comic Library 路徑
            VStack(alignment: .leading, spacing: 8) {
                Label("Comic Library", systemImage: "folder")
                    .font(.headline)

                HStack {
                    if let url = settings.libraryURL {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(url.path)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundColor(.secondary)
                        Text("尚未設定路徑")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    Spacer()
                    Button("選擇資料夾") {
                        settings.pickLibraryFolder()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Divider()

            // iCloud 同步
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("iCloud 同步", systemImage: "icloud")
                        .font(.headline)
                    Spacer()
                    Button {
                        showICloudHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showICloudHelp, arrowEdge: .top) {
                        ICloudHelpView()
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("同步書籤與閱讀紀錄")
                                .font(.system(size: 13))
                            Text("資料將存至 iCloud Drive，跨裝置共用")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.iCloudSyncEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .onChange(of: settings.iCloudSyncEnabled) { _, enabled in
                        if enabled {
                            bookmarks.enableICloud()
                            progressStore.enableICloud()
                        } else {
                            bookmarks.disableICloud()
                            progressStore.disableICloud()
                        }
                    }

                    Divider()

                    iCloudRow(label: "書籤",
                              isEnabled: settings.iCloudSyncEnabled,
                              isActive: bookmarks.isUsingiCloud,
                              attempted: bookmarks.cloudResolutionAttempted)
                    iCloudRow(label: "閱讀紀錄",
                              isEnabled: settings.iCloudSyncEnabled,
                              isActive: progressStore.isUsingiCloud,
                              attempted: progressStore.cloudResolutionAttempted)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Divider()

            // 下載管理
            VStack(alignment: .leading, spacing: 8) {
                Label("書籤下載", systemImage: "arrow.down.circle")
                    .font(.headline)

                let downloaded = bookmarks.bookmarks.filter { downloads.isDownloaded($0) }.count
                let total = bookmarks.bookmarks.count

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已下載 \(downloaded) / \(total) 本")
                            .font(.system(size: 13))
                        if total > 0 {
                            ProgressView(value: Double(downloaded), total: Double(total))
                                .frame(width: 200)
                        }
                    }
                    Spacer()
                    Button {
                        downloads.downloadAll(bookmarks: bookmarks.bookmarks)
                    } label: {
                        Label("全部下載", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.libraryURL == nil || downloaded == total)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // 下載中列表
            let activeDownloads = bookmarks.bookmarks.filter { downloads.states[$0.id]?.isActive == true }
            if !activeDownloads.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("下載中")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach(activeDownloads) { gallery in
                        DownloadProgressRow(gallery: gallery)
                    }
                }
            }

            Divider()

            // 閱讀設定
            VStack(alignment: .leading, spacing: 8) {
                Label("閱讀設定", systemImage: "book")
                    .font(.headline)

                HStack {
                    Text("往前預讀張數")
                        .font(.system(size: 13))
                    Spacer()
                    Stepper("\(settings.prefetchCount) 張",
                            value: $settings.prefetchCount, in: 1...20)
                        .fixedSize()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Divider()

            // 圖片快取
            VStack(alignment: .leading, spacing: 8) {
                Label("圖片快取", systemImage: "internaldrive")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("磁碟快取大小：\(cacheSizeString)")
                            .font(.system(size: 13))
                        Text(cacheLocation)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("清除快取") {
                        Task {
                            await ImageLoader.shared.clearDiskCache()
                            cacheSize = await ImageLoader.shared.diskCacheSize()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            cacheSize = await ImageLoader.shared.diskCacheSize()
        }
        .onChange(of: settings.libraryURL) { _, _ in
            Task { cacheSize = await ImageLoader.shared.diskCacheSize() }
        }
    }

    @ViewBuilder
    private func iCloudRow(label: String, isEnabled: Bool, isActive: Bool, attempted: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if isActive {
                    Image(systemName: "checkmark.icloud.fill").foregroundColor(.accentColor)
                } else if isEnabled && attempted {
                    // iCloud 解析已完成但失敗（無 entitlement 或未登入）
                    Image(systemName: "xmark.icloud").foregroundColor(.red)
                } else if isEnabled {
                    // 尚未嘗試完成
                    Image(systemName: "icloud").foregroundColor(.orange)
                } else {
                    Image(systemName: "xmark.icloud").foregroundColor(.secondary)
                }
            }
            .font(.system(size: 14))

            Text(label).font(.system(size: 13))
            Spacer()

            if isActive {
                Text("同步中").font(.system(size: 12)).foregroundColor(.accentColor)
            } else if isEnabled && attempted {
                Text("無法連線").font(.system(size: 12)).foregroundColor(.red)
            } else if isEnabled {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    Text("連線中").font(.system(size: 12)).foregroundColor(.orange)
                }
            } else {
                Text("已停用").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private var cacheSizeString: String {
        let mb = Double(cacheSize) / 1_048_576
        if mb < 1 { return "\(cacheSize / 1024) KB" }
        return String(format: "%.1f MB", mb)
    }

    private var cacheLocation: String {
        if let path = settings.libraryURL?.path {
            return "\(path)/.cache/"
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.comic.imagecache").path
    }
}

struct DownloadProgressRow: View {
    let gallery: Gallery
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        let state = downloads.states[gallery.id] ?? .notDownloaded
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gallery.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                switch state {
                case .downloading(let p, let t):
                    ProgressView(value: Double(p), total: Double(t))
                    Text("\(p) / \(t) 頁")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .packaging:
                    ProgressView()
                    Text("打包中…")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .queued:
                    Text("等待中…")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                default: EmptyView()
                }
            }
            Spacer()
            Button {
                downloads.cancelDownload(gallery: gallery)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct ICloudHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("如何啟用 iCloud 同步", systemImage: "icloud")
                .font(.headline)

            Text("此 App 透過 **iCloud Drive** 同步書籤與閱讀紀錄。")
                .font(.system(size: 13))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                helpStep(number: "1", text: "點選左上角 Apple 選單 → **系統設定**")
                helpStep(number: "2", text: "點選頂部 **Apple ID**")
                helpStep(number: "3", text: "點選 **iCloud**")
                helpStep(number: "4", text: "開啟 **iCloud Drive**")
                helpStep(number: "5", text: "回到本 App，重新開關「同步書籤與閱讀紀錄」")
            }

            Divider()

            Text("同步後資料存放於：")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("iCloud Drive / Comic /")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private func helpStep(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
        }
    }
}
