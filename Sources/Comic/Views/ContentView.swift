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

    enum SidebarTab { case browse, bookmarks, settings }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 分頁按鈕 + 來源下拉選單
                HStack(spacing: 0) {
                    tabButton(title: "瀏覽", icon: "rectangle.grid.2x2", tab: .browse)
                    tabButton(title: "書籤", icon: "bookmark", tab: .bookmarks)
                    tabButton(title: "設定", icon: "gearshape", tab: .settings)

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
                case .settings:  SettingsView()
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 500)
        } detail: {
            if showChapterList, let gallery = selectedGallery {
                ChapterListView(gallery: gallery, onSelect: { ch, all, page in openChapter(ch, allChapters: all, startPage: page) }, onBack: {
                    showChapterList = false
                    showReader = false
                })
                .id(gallery.id)  // 切換漫畫時強制重新載入章節列表
            } else if showReader {
                VStack(spacing: 0) {
                    if !isFullscreen {
                        HStack {
                            Button {
                                if selectedGallery?.sourceID == .manhuagui {
                                    showChapterList = true
                                } else {
                                    showReader = false
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                Text(selectedGallery?.sourceID == .manhuagui ? "章節" : "返回")
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
    }

    private func gallerySelected(_ gallery: Gallery) {
        selectedGallery = gallery
        if gallery.sourceID == .manhuagui {
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

    private func tabButton(title: String, icon: String, tab: SidebarTab) -> some View {
        Button {
            sidebarTab = tab
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
