import SwiftUI

@MainActor
final class GalleryListViewModel: ObservableObject {
    @Published var galleries: [Gallery] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText = ""
    /// 目前選擇的篩選值：groupID → optionID（"" 代表全部）
    @Published var selectedFilters: [String: String] = [:]

    @Published var currentPage = 1
    @Published var totalPages = 1
    @Published var totalResults = 0

    private var cursors: [String?] = [nil]
    private var lastSearch = ""
    private var lastFilters: [String: String] = [:]
    private var currentSource: ComicSource = SourceManager.shared.activeSource

    // MARK: - 狀態持久化

    private func stateKey(_ suffix: String) -> String {
        "browse.\(currentSource.sourceID.rawValue).\(suffix)"
    }

    private func saveState() {
        let ud = UserDefaults.standard
        ud.set(currentPage, forKey: stateKey("page"))
        ud.set(lastSearch,  forKey: stateKey("search"))
        if let data = try? JSONEncoder().encode(lastFilters) {
            ud.set(data, forKey: stateKey("filters"))
        }
    }

    private func restoreSavedState() -> (page: Int, search: String, filters: [String: String]) {
        let ud = UserDefaults.standard
        let page    = max(1, ud.integer(forKey: stateKey("page")))
        let search  = ud.string(forKey: stateKey("search")) ?? ""
        var filters: [String: String] = [:]
        if let data = ud.data(forKey: stateKey("filters")),
           let f = try? JSONDecoder().decode([String: String].self, from: data) {
            filters = f
        }
        return (page, search, filters)
    }

    // MARK: - 來源切換（恢復記憶狀態）

    func switchToSource(_ source: ComicSource) async {
        currentSource = source
        cursors = [nil]; totalPages = 1; totalResults = 0; galleries = []

        let saved = restoreSavedState()
        searchText      = saved.search
        lastSearch      = saved.search
        selectedFilters = saved.filters
        lastFilters     = saved.filters

        if saved.page > 1 {
            await goToPage(saved.page)
        } else {
            await load(cursorIndex: 0)
        }
    }

    // MARK: - 載入

    func load(cursorIndex: Int) async {
        guard cursorIndex >= 0 else { return }
        isLoading = true; error = nil; galleries = []
        do {
            var extra: [String: Any] = [:]
            if currentSource.sourceID == .ehentai {
                guard cursorIndex < cursors.count else { isLoading = false; return }
                extra["cursor"] = cursors[cursorIndex]
            }
            let page = cursorIndex + 1
            let result = try await currentSource.fetchList(
                page: page, search: lastSearch, filters: lastFilters, extra: extra)
            galleries    = result.galleries
            currentPage  = result.currentPage
            totalPages   = result.totalPages
            totalResults = result.totalResults
            if currentSource.sourceID == .ehentai,
               let next = result.nextCursor, cursorIndex + 1 >= cursors.count {
                cursors.append(next)
                totalPages = max(cursors.count, totalPages)
            }
            saveState()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func search() async {
        lastSearch  = searchText
        lastFilters = selectedFilters
        cursors = [nil]; totalPages = 1; totalResults = 0
        await load(cursorIndex: 0)
    }

    func nextPage() async { await goToPage(currentPage + 1) }
    func prevPage() async { guard currentPage > 1 else { return }; await load(cursorIndex: currentPage - 2) }

    func goToPage(_ page: Int) async {
        let idx = page - 1
        if currentSource.sourceID != .ehentai {
            await load(cursorIndex: idx); return
        }
        if idx < cursors.count {
            await load(cursorIndex: idx)
        } else {
            // 逐頁走訪以收集 cursor，再載入目標頁
            for i in (cursors.count - 1)..<idx {
                await load(cursorIndex: i)
                if i + 1 >= cursors.count { break }  // 沒有下一頁 cursor，停止
            }
            // 現在 cursors 已包含目標頁 cursor，載入目標頁
            if idx < cursors.count {
                await load(cursorIndex: idx)
            }
        }
    }
}

// MARK: - View

struct GalleryListView: View {
    @StateObject private var vm = GalleryListViewModel()
    @ObservedObject private var sourceMgr = SourceManager.shared
    let onSelect: (Gallery) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // 搜尋列
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜尋...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await vm.search() } }
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = ""; Task { await vm.search() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 篩選列（各來源自定義）
            if !sourceMgr.activeSource.filterGroups.isEmpty {
                FilterBarView(
                    groups: sourceMgr.activeSource.filterGroups,
                    selected: $vm.selectedFilters
                ) { Task { await vm.search() } }
            }

            Divider()

            if vm.isLoading && vm.galleries.isEmpty {
                Spacer()
                ProgressView("載入中...")
                Spacer()
            } else if let error = vm.error, vm.galleries.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(error).foregroundColor(.secondary)
                    Button("重試") { Task { await vm.load(cursorIndex: vm.currentPage - 1) } }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.galleries) { gallery in
                            GalleryCard(gallery: gallery)
                                .onTapGesture { onSelect(gallery) }
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(gallery.galleryURL.absoluteString, forType: .string)
                                    } label: {
                                        Label("複製漫畫連結", systemImage: "link")
                                    }
                                }
                        }
                    }
                    .padding(10)
                }

                Divider()

                PaginationView(current: vm.currentPage, total: vm.totalPages, isLoading: vm.isLoading) { page in
                    Task { await vm.goToPage(page) }
                }
            }
        }
        .task { await vm.switchToSource(sourceMgr.activeSource) }
        .onChange(of: sourceMgr.activeSourceID) {
            Task { await vm.switchToSource(sourceMgr.activeSource) }
        }
    }
}

// MARK: - 分頁控制

struct PaginationView: View {
    let current: Int      // 1-based
    let total: Int        // 總頁數
    let isLoading: Bool
    let onGo: (Int) -> Void   // 傳入 1-based 頁碼

    @State private var inputText = ""

    // 產生要顯示的頁碼清單（nil 代表 ...）
    private var pageItems: [Int?] {
        guard total > 1 else { return [1] }
        var pages = Set<Int>()
        pages.formUnion([1, 2])
        pages.formUnion([total - 1, total].filter { $0 >= 1 })
        for p in (current - 2)...(current + 2) { if p >= 1 && p <= total { pages.insert(p) } }
        let sorted = pages.sorted()
        var result: [Int?] = []
        var prev = 0
        for p in sorted {
            if p - prev > 1 { result.append(nil) }
            result.append(p)
            prev = p
        }
        return result
    }

    var body: some View {
        HStack(spacing: 4) {
            // |<
            pageButton(label: "|‹", page: 1, disabled: current == 1)
            // <
            pageButton(label: "‹", page: current - 1, disabled: current == 1)

            // 頁碼列
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(pageItems.indices, id: \.self) { i in
                        if let p = pageItems[i] {
                            let isActive = p == current
                            Button { onGo(p) } label: {
                                Text("\(p)")
                                    .font(.system(size: 12, weight: isActive ? .bold : .regular))
                                    .foregroundColor(isActive ? .white : .primary)
                                    .frame(minWidth: 28, minHeight: 24)
                                    .background(isActive ? Color.accentColor : Color.clear)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                        } else {
                            Text("…")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 20)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)

            // >
            pageButton(label: "›", page: current + 1, disabled: current >= total)
            // >|
            pageButton(label: "›|", page: total, disabled: current >= total)

            Divider().frame(height: 20).padding(.horizontal, 4)

            // 跳頁輸入框
            HStack(spacing: 4) {
                Text("跳至")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 46)
                    .onSubmit { commitJump() }
                Text("/ \(total)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func pageButton(label: String, page: Int, disabled: Bool) -> some View {
        Button { onGo(page) } label: {
            Text(label)
                .font(.system(size: 12))
                .frame(minWidth: 28, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .disabled(disabled || isLoading)
    }

    private func commitJump() {
        if let n = Int(inputText), n >= 1, n <= total {
            onGo(n)
        }
        inputText = ""
    }
}

// MARK: - 篩選列（通用，各來源自定義 FilterGroup）

struct FilterBarView: View {
    let groups: [FilterGroup]
    @Binding var selected: [String: String]
    let onApply: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(groups) { group in
                    filterMenu(group)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func filterMenu(_ group: FilterGroup) -> some View {
        let currentID    = selected[group.id] ?? ""
        let currentLabel = group.options.first(where: { $0.id == currentID })?.label ?? group.options[0].label
        let isActive     = !currentID.isEmpty

        Menu {
            ForEach(group.options) { opt in
                Button {
                    selected[group.id] = opt.id
                    onApply()
                } label: {
                    if (selected[group.id] ?? "") == opt.id {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(group.label + ": " + currentLabel)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .white : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: isActive ? 0 : 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - 圖庫卡片

struct GalleryCard: View {
    let gallery: Gallery
    @State private var thumb: NSImage?
    @ObservedObject private var bookmarks = BookmarkStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 縮圖
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color(NSColor.controlBackgroundColor)
                    if let img = thumb {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 220)
                .clipped()

                // 書籤按鈕
                Button {
                    bookmarks.toggle(gallery)
                } label: {
                    Image(systemName: bookmarks.isBookmarked(gallery) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13))
                        .foregroundColor(bookmarks.isBookmarked(gallery) ? .yellow : .white)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .cornerRadius(6, corners: [.topLeft, .topRight])

            // 標題與資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(gallery.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let pages = gallery.pageCount {
                    Text("\(pages) 頁")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .task {
            if let url = gallery.thumbURL {
                thumb = await ImageLoader.shared.image(for: url)
            }
        }
    }
}

// MARK: - 圓角 Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerShape: Shape {
    let radius: CGFloat
    let corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - 自動換行排版

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
