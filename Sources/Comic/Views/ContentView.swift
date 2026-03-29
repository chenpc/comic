import SwiftUI

struct ContentView: View {
    @StateObject private var readerVM = ReaderViewModel()
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var sourceMgr = SourceManager.shared
    @State private var selectedGallery: Gallery?
    @State private var showReader = false
    @State private var showChapterList = false
    @State private var sidebarTab: SidebarTab = .browse
    @State private var isFullscreen = false
    @State private var libraryGallery: Gallery?   // library 模式下選中的漫畫

    enum SidebarTab { case browse, bookmarks, library, settings }

    var body: some View {
        // 全螢幕閱讀時跳過 NavigationSplitView，確保 toolbar 完全消失
        if isFullscreen && showReader {
            ReaderView(vm: readerVM, isFullscreen: true)
                .ignoresSafeArea()
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                    isFullscreen = false
                }
        } else {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 分頁按鈕 + 來源下拉選單
                HStack(spacing: 0) {
                    tabButton(title: "瀏覽", icon: "rectangle.grid.2x2", tab: .browse) { libraryGallery = nil }
                    tabButton(title: "書籤", icon: "bookmark", tab: .bookmarks) { libraryGallery = nil }
                    tabButton(title: "Library", icon: "internaldrive", tab: .library) {}
                    tabButton(title: "設定", icon: "gearshape", tab: .settings) { libraryGallery = nil }

                    Divider().frame(width: 1, height: 20).padding(.horizontal, 4)

                    Picker("", selection: $sourceMgr.activeSourceID) {
                        ForEach(SourceID.allCases) { src in
                            HStack {
                                Image(systemName: src.iconName)
                                Text(src.displayName)
                            }.tag(src)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)
                    .padding(.trailing, 4)
                }
                .padding(8)

                Divider()

                switch sidebarTab {
                case .browse:    GalleryListView(onSelect: gallerySelected)
                case .bookmarks: BookmarkView(store: bookmarks, onSelect: gallerySelected)
                case .library:
                    LibraryView(
                        onSelectGallery: { gallery in
                            libraryGallery = gallery
                            selectedGallery = gallery
                            showChapterList = true
                            showReader = false
                        },
                        onSelectChapter: { chapter, allChapters, startPage, gallery in
                            libraryGallery = gallery
                            openLibraryChapter(chapter, gallery: gallery, allChapters: allChapters, startPage: startPage)
                        }
                    )
                case .settings:  SettingsView()
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 500)
        } detail: {
            if showChapterList, let gallery = selectedGallery {
                if libraryGallery?.id == gallery.id {
                    // Library 模式：從本地檔案系統列出章節
                    LocalChapterListView(
                        gallery: gallery,
                        onSelect: { ch, all, page in
                            openLibraryChapter(ch, gallery: gallery, allChapters: all, startPage: page)
                        },
                        onBack: {
                            showChapterList = false
                            showReader = false
                            libraryGallery = nil
                        }
                    )
                    .id(gallery.id)
                } else {
                    ChapterListView(gallery: gallery, onSelect: { ch, all, page in openChapter(ch, allChapters: all, startPage: page) }, onBack: {
                        showChapterList = false
                        showReader = false
                    })
                    .id(gallery.id)
                }
            } else if showReader {
                VStack(spacing: 0) {
                    if !isFullscreen {
                        HStack {
                            Button {
                                if libraryGallery != nil {
                                    showReader = false
                                    showChapterList = true
                                } else if selectedGallery.map({ SourceManager.shared.source(for: $0.sourceID).hasChapters }) == true {
                                    showChapterList = true
                                } else {
                                    showReader = false
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                Text(libraryGallery != nil ? "章節"
                                     : (selectedGallery.map { SourceManager.shared.source(for: $0.sourceID).hasChapters } == true) ? "章節" : "返回")
                            }
                            .buttonStyle(.borderless)

                            Spacer()

                            HStack(spacing: 6) {
                                if readerVM.isLocalFile {
                                    Image(systemName: "internaldrive")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                } else {
                                    Image(systemName: "network")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                }
                                if !readerVM.galleryTitle.isEmpty {
                                    Text(readerVM.galleryTitle)
                                        .font(.headline)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if readerVM.totalPages > 0 {
                                Button {
                                    readerVM.jumpSheetVisible = true
                                } label: {
                                    Text("\(readerVM.currentIndex + 1) / \(readerVM.totalPages)")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.windowBackgroundColor))

                        Divider()
                    }

                    ReaderView(vm: readerVM, isFullscreen: isFullscreen)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                    isFullscreen = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                    isFullscreen = false
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("從左側選擇圖庫開始閱讀")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: Binding(
            get: { readerVM.jumpSheetVisible },
            set: { readerVM.jumpSheetVisible = $0 }
        )) {
            JumpSheet(vm: readerVM)
        }
        } // end else (非全螢幕)
    }

    private func gallerySelected(_ gallery: Gallery) {
        selectedGallery = gallery
        let src = SourceManager.shared.source(for: gallery.sourceID)
        if src.hasChapters {
            showChapterList = true
            showReader = false
        } else {
            showChapterList = false
            showReader = true
            Task { await readerVM.loadGallery(gallery) }
        }
    }

    private func openChapter(_ chapter: Chapter, allChapters: [Chapter], startPage: Int = 0) {
        showChapterList = false
        showReader = true
        let gallery = selectedGallery
        Task { await readerVM.loadChapter(chapter, gallery: gallery, allChapters: allChapters, startPage: startPage) }
    }

    private func openLibraryChapter(_ chapter: Chapter, gallery: Gallery, allChapters: [Chapter], startPage: Int = 0) {
        print("[Library] openLibraryChapter: \(chapter.title) url=\(chapter.url)")
        showChapterList = false
        showReader = true
        Task { await readerVM.loadChapter(chapter, gallery: gallery, allChapters: allChapters, startPage: startPage) }
    }

    private func tabButton(title: String, icon: String, tab: SidebarTab, extra: (() -> Void)? = nil) -> some View {
        Button {
            sidebarTab = tab
            extra?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sidebarTab == tab ? "\(icon).fill" : icon)
                Text(title)
            }
            .font(.system(size: 12, weight: sidebarTab == tab ? .semibold : .regular))
            .foregroundColor(sidebarTab == tab ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(sidebarTab == tab ? Color.accentColor.opacity(0.12) : .clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 跳頁 Sheet

struct JumpSheet: View {
    @ObservedObject var vm: ReaderViewModel
    @State private var input = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("跳到第幾頁").font(.headline)
            HStack {
                TextField("頁碼", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onAppear { input = "\(vm.currentIndex + 1)" }
                    .onSubmit { confirm() }
                Text("/ \(vm.totalPages)").foregroundColor(.secondary)
            }
            HStack {
                Button("取消") { vm.jumpSheetVisible = false }
                    .keyboardShortcut(.cancelAction)
                Button("確定") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 220)
    }

    private func confirm() {
        if let page = Int(input), page >= 1, page <= vm.totalPages {
            vm.jumpTo(page: page - 1)
        }
        vm.jumpSheetVisible = false
    }
}
