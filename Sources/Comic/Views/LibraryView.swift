import SwiftUI

// MARK: - LibraryView

struct LibraryView: View {
    /// 選擇漫畫後的回呼（由 ContentView 負責在 detail pane 顯示章節列表）
    let onSelectGallery: (Gallery) -> Void
    /// ehentai 單一 CBZ 直接開閱讀器
    let onSelectChapter: (Chapter, [Chapter], Int, Gallery) -> Void

    @State private var galleries: [Gallery] = []
    @State private var isScanning = false

    var body: some View {
        galleryGridView
            .task { await scan() }
    }

    // MARK: - Gallery Grid

    private var galleryGridView: some View {
        VStack(spacing: 0) {
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
                        ForEach(galleries) { gallery in
                            LocalGalleryCard(gallery: gallery) {
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
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Scan

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        guard let lib = SettingsStore.shared.libraryURL else { return }
        let fm = FileManager.default
        var found: [Gallery] = []

        // 掃描各來源子目錄
        for sourceID in SourceID.allCases {
            let sourceDir = lib.appendingPathComponent(sourceID.rawValue)
            guard fm.fileExists(atPath: sourceDir.path) else { continue }

            let items = (try? fm.contentsOfDirectory(
                at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []

            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }

                switch sourceID {
                case .ehentai:
                    // 單一 CBZ 檔案：{id}.cbz
                    guard item.pathExtension.lowercased() == "cbz" else { continue }
                    let id = item.deletingPathExtension().lastPathComponent
                    let gallery = Gallery(
                        id: id,
                        token: id,
                        title: id,
                        thumbURL: nil,
                        pageCount: nil,
                        category: nil,
                        uploader: nil,
                        source: sourceID.rawValue,
                        galleryURL: item
                    )
                    found.append(gallery)

                default:
                    // 章節資料夾：每個子資料夾是一部漫畫
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let cbzCount = ((try? fm.contentsOfDirectory(
                        at: item, includingPropertiesForKeys: nil)) ?? [])
                        .filter { $0.pathExtension.lowercased() == "cbz" }.count
                    guard cbzCount > 0 else { continue }
                    let gallery = Gallery(
                        id: "\(sourceID.rawValue)_\(name)",
                        token: name,
                        title: name,
                        thumbURL: nil,
                        pageCount: cbzCount,
                        category: nil,
                        uploader: nil,
                        source: sourceID.rawValue,
                        galleryURL: item
                    )
                    found.append(gallery)
                }
            }
        }

        galleries = found
    }
}

// MARK: - LocalGalleryCard

private struct LocalGalleryCard: View {
    let gallery: Gallery
    let onTap: () -> Void

    @State private var thumb: NSImage?

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

    private func firstImage(in dir: URL) -> NSImage? {
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

