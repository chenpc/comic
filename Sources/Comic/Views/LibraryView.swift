import SwiftUI

// MARK: - LibraryView

struct LibraryView: View {
    /// 選擇漫畫後的回呼（由 ContentView 負責在 detail pane 顯示章節列表）
    let onSelectGallery: (Gallery) -> Void
    /// ehentai 單一 CBZ 直接開閱讀器
    let onSelectChapter: (Chapter, [Chapter], Int, Gallery) -> Void

    @State private var galleries: [Gallery] = []       // 已按修改時間排序（新→舊）
    @State private var isScanning = false
    @State private var searchText = ""
    @State private var selectedSource: SourceID? = nil  // nil = 全部
    @State private var currentPage = 1

    private let pageSize = 40

    /// 目前 library 中有內容的來源（用於顯示 tabs）
    private var availableSources: [SourceID] {
        let ids = Set(galleries.map { $0.sourceID })
        return SourceID.allCases.filter { ids.contains($0) }
    }

    private var filteredGalleries: [Gallery] {
        let bySource = selectedSource == nil ? galleries : galleries.filter { $0.sourceID == selectedSource }
        return Self.filterGalleries(bySource, query: searchText)
    }

    private var totalPages: Int { max(1, Int(ceil(Double(filteredGalleries.count) / Double(pageSize)))) }

    private var pagedGalleries: [Gallery] {
        let start = (currentPage - 1) * pageSize
        guard start < filteredGalleries.count else { return [] }
        return Array(filteredGalleries[start..<min(start + pageSize, filteredGalleries.count)])
    }

    static func filterGalleries(_ galleries: [Gallery], query: String) -> [Gallery] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return galleries }
        return galleries.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        galleryGridView
            .task { await scan() }
            .onChange(of: selectedSource) { _, _ in currentPage = 1 }
            .onChange(of: searchText)    { _, _ in currentPage = 1 }
    }

    // MARK: - Gallery Grid

    private var galleryGridView: some View {
        VStack(spacing: 0) {
            // 來源篩選 tabs（有多個來源才顯示）
            if !galleries.isEmpty && availableSources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        sourceTab(id: nil, label: "全部")
                        ForEach(availableSources) { src in
                            sourceTab(id: src, label: src.displayName)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                Divider()
            }

            // 搜尋欄
            if !galleries.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜尋漫畫櫃…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            if isScanning {
                Spacer()
                ProgressView("掃描 Library…")
                Spacer()
            } else if galleries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Library 沒有已下載的漫畫")
                        .foregroundColor(.secondary)
                    Text("請先下載漫畫章節")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(pagedGalleries) { gallery in
                            LocalGalleryCard(gallery: gallery, onTap: {
                                if gallery.sourceID == .ehentai {
                                    let dummyChapter = Chapter(
                                        id: gallery.id,
                                        title: gallery.title,
                                        url: gallery.galleryURL,
                                        pageCount: nil
                                    )
                                    onSelectChapter(dummyChapter, [], 0, gallery)
                                } else {
                                    onSelectGallery(gallery)
                                }
                            }, onDelete: {
                                deleteGallery(gallery)
                            })
                        }
                    }
                    .padding(12)
                }

                if totalPages > 1 {
                    Divider()
                    LibraryPaginationView(current: $currentPage, total: totalPages)
                }
            }
        }
    }

    // MARK: - Source Tab

    private func sourceTab(id: SourceID?, label: String) -> some View {
        let isActive = selectedSource == id
        return Button { selectedSource = id } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: isActive ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete

    private func deleteGallery(_ gallery: Gallery) {
        let fm = FileManager.default
        if gallery.sourceID == .ehentai {
            try? fm.removeItem(at: gallery.galleryURL)
        } else {
            try? fm.removeItem(at: gallery.galleryURL)
        }
        galleries.removeAll { $0.id == gallery.id }
    }

    // MARK: - Scan

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        guard let lib = SettingsStore.shared.libraryURL else { return }
        let fm = FileManager.default
        // (Gallery, modificationDate) 暫存，掃完後排序
        var found: [(Gallery, Date)] = []

        let dateKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

        // 掃描各來源子目錄
        for sourceID in SourceID.allCases {
            let sourceDir = lib.appendingPathComponent(sourceID.rawValue)
            guard fm.fileExists(atPath: sourceDir.path) else { continue }

            let items = (try? fm.contentsOfDirectory(
                at: sourceDir, includingPropertiesForKeys: dateKeys)) ?? []

            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }

                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast

                switch sourceID {
                case .ehentai:
                    guard item.pathExtension.lowercased() == "cbz" else { continue }
                    let id = item.deletingPathExtension().lastPathComponent
                    let gallery = Gallery(
                        id: id, token: id, title: id,
                        thumbURL: nil, pageCount: nil, category: nil, uploader: nil,
                        source: sourceID.rawValue, galleryURL: item
                    )
                    found.append((gallery, modDate))

                default:
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let cbzCount = ((try? fm.contentsOfDirectory(
                        at: item, includingPropertiesForKeys: nil)) ?? [])
                        .filter { $0.pathExtension.lowercased() == "cbz" }.count
                    guard cbzCount > 0 else { continue }
                    let gallery = Gallery(
                        id: "\(sourceID.rawValue)_\(name)", token: name, title: name,
                        thumbURL: nil, pageCount: cbzCount, category: nil, uploader: nil,
                        source: sourceID.rawValue, galleryURL: item
                    )
                    found.append((gallery, modDate))
                }
            }
        }

        // 按修改時間排序（最新在前）
        galleries = found
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        currentPage = 1
    }
}

// MARK: - LibraryPaginationView

private struct LibraryPaginationView: View {
    @Binding var current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Button { current = max(1, current - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(current <= 1)

            // 頁碼 (最多顯示 5 個)
            ForEach(visiblePages, id: \.self) { page in
                if page == -1 {
                    Text("…").foregroundColor(.secondary).font(.system(size: 12))
                } else {
                    Button("\(page)") { current = page }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: current == page ? .bold : .regular))
                        .foregroundColor(current == page ? .accentColor : .primary)
                        .frame(minWidth: 24)
                        .padding(.vertical, 2)
                        .background(current == page ? Color.accentColor.opacity(0.12) : .clear)
                        .cornerRadius(4)
                }
            }

            Button { current = min(total, current + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(current >= total)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var visiblePages: [Int] {
        guard total > 1 else { return [1] }
        var pages = Set<Int>()
        pages.formUnion([1, total])
        for p in max(1, current - 1)...min(total, current + 1) { pages.insert(p) }
        let sorted = pages.sorted()
        var result: [Int] = []
        var prev = 0
        for p in sorted {
            if p - prev > 1 { result.append(-1) }   // 省略號
            result.append(p)
            prev = p
        }
        return result
    }
}

// MARK: - LocalGalleryCard

private struct LocalGalleryCard: View {
    let gallery: Gallery
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumb: NSImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color(NSColor.controlBackgroundColor)
                    if let img = thumb {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: gallery.sourceID == .ehentai
                              ? "photo.on.rectangle.angled" : "books.vertical")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 220)
                .clipped()
                .cornerRadius(6, corners: [.topLeft, .topRight])

                VStack(alignment: .leading, spacing: 2) {
                    Text(gallery.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    HStack(spacing: 4) {
                        Image(systemName: gallery.sourceID.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        if let cnt = gallery.pageCount {
                            Text("\(cnt) 集")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(6, corners: [.bottomLeft, .bottomRight])
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await loadThumb() }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
        .confirmationDialog("確定刪除「\(gallery.title)」？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作將刪除磁碟上的所有檔案，無法復原。")
        }
    }

    private func loadThumb() async {
        guard thumb == nil else { return }
        // 從第一個章節 CBZ 取首張圖作縮圖
        if gallery.sourceID != .ehentai {
            let folder = gallery.galleryURL
            guard let cbz = ((try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter({ $0.pathExtension.lowercased() == "cbz" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first else { return }
            thumb = await extractFirstImage(from: cbz)
        } else {
            thumb = await extractFirstImage(from: gallery.galleryURL)
        }
    }

    private func extractFirstImage(from cbz: URL) async -> NSImage? {
        await withCheckedContinuation { cont in
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("lib_thumb_\(cbz.deletingPathExtension().lastPathComponent)")
            let fm = FileManager.default
            // 若已解壓，直接取
            if fm.fileExists(atPath: tmp.path),
               let img = firstImage(in: tmp) {
                cont.resume(returning: img)
                return
            }
            do { try fm.createDirectory(at: tmp, withIntermediateDirectories: true) } catch {}
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            // 只解壓第一頁
            proc.arguments = ["-o", cbz.path, "-d", tmp.path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            proc.terminationHandler = { _ in
                cont.resume(returning: self.firstImage(in: tmp))
            }
            try? proc.run()
        }
    }

    nonisolated private func firstImage(in dir: URL) -> NSImage? {
        let exts = Set(["jpg", "jpeg", "png", "webp"])
        guard let first = ((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter({ exts.contains($0.pathExtension.lowercased()) })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .first else { return nil }
        return NSImage(contentsOf: first)
    }
}

// MARK: - LocalChapterListView

struct LocalChapterListView: View {
    let gallery: Gallery
    let onSelect: (Chapter, [Chapter], Int) -> Void
    let onBack: () -> Void

    @State private var chapters: [Chapter] = []
    @ObservedObject private var progressStore = ReadingProgressStore.shared

    private var lastRead: ReadingProgress? { progressStore.lastRead(galleryID: gallery.id) }

    private var displayChapters: [Chapter] {
        guard let last = lastRead,
              let idx = chapters.firstIndex(where: { $0.url.absoluteString == last.chapterURL.absoluteString }),
              idx != 0 else { return chapters }
        var reordered = chapters
        let pinned = reordered.remove(at: idx)
        reordered.insert(pinned, at: 0)
        return reordered
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

            if !chapters.isEmpty {
                if let last = lastRead,
                   let chapter = chapters.first(where: {
                       $0.url.absoluteString == last.chapterURL.absoluteString
                   }) {
                    continueBanner(chapter: chapter, pageIndex: last.pageIndex)
                    Divider()
                }
            }

            if chapters.isEmpty {
                Spacer()
                Text("沒有找到章節").foregroundColor(.secondary)
                Spacer()
            } else {
                List(displayChapters) { chapter in
                    Button {
                        print("[Library] chapter tapped: \(chapter.title) url=\(chapter.url)")
                        onSelect(chapter, chapters, 0)
                    } label: {
                        HStack {
                            Image(systemName: chapter.url.absoluteString == lastRead?.chapterURL.absoluteString
                                  ? "bookmark.fill" : "internaldrive")
                                .foregroundColor(chapter.url.absoluteString == lastRead?.chapterURL.absoluteString
                                                 ? .accentColor : .green)
                                .frame(width: 20)
                            Text(chapter.title)
                                .font(.system(size: 13))
                                .foregroundColor(chapter.url.absoluteString == lastRead?.chapterURL.absoluteString
                                                 ? .accentColor : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { scanChapters() }
    }

    private func continueBanner(chapter: Chapter, pageIndex: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill").foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("上次看到").font(.system(size: 10)).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(chapter.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if pageIndex > 0 {
                        Text("第 \(pageIndex + 1) 頁").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button("繼續閱讀") { onSelect(chapter, chapters, pageIndex) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private func scanChapters() {
        let folder = gallery.galleryURL
        print("[Library] scanChapters folder=\(folder.path)")
        let cbzFiles = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "cbz" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        print("[Library] found \(cbzFiles.count) cbz files")
        chapters = cbzFiles.map { cbz in
            let title = cbz.deletingPathExtension().lastPathComponent
            return Chapter(id: title, title: title, url: cbz, pageCount: nil)
        }
    }
}

