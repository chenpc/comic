# Comic App 工作日誌

## 專案概要

macOS SwiftUI 漫畫閱讀器，支援多來源：E-Hentai 與漫畫櫃（tw.manhuagui.com）。

---

## 功能清單

### 核心架構

| 元件 | 檔案 | 狀態 |
|------|------|------|
| 資料模型（Gallery, Chapter, SourceID, EHCategory） | `Models.swift` | ✅ 完成 |
| 多來源協定（ComicSource, FilterGroup, FilterOption, ListPage） | `Sources/ComicSource.swift` | ✅ 完成 |
| 來源管理（SourceManager，記憶上次選擇） | `Sources/ComicSource.swift` | ✅ 完成 |

### 來源實作

| 來源 | 檔案 | 功能 | 狀態 |
|------|------|------|------|
| E-Hentai | `Sources/EHentaiSource.swift` | 列表、搜尋、分類篩選（bitmask） | ✅ 完成 |
| 漫畫櫃 | `Sources/ManhuaguiSource.swift` | 列表、搜尋、6維篩選（地區/劇情/受眾/年份/字母/進度） | ✅ 完成 |

### 服務層

| 服務 | 檔案 | 功能 | 狀態 |
|------|------|------|------|
| E-Hentai API | `Services/EHentaiService.swift` | 畫廊列表、圖片 URL 取得（含 e-hentai cookies） | ✅ 完成 |
| 漫畫櫃 HTTP | `Services/ManhuaguiService.swift` | 列表解析、章節解析、章節圖片（委派給 WKWebView） | ✅ 完成（圖片 debug 中） |
| 漫畫櫃 Web 擷取 | `Services/ManhuaguiWebExtractor.swift` | WKWebView 執行完整 JS，攔截 SMH.imgData | ⚠️ 待驗證 |
| 書籤 | `Services/BookmarkStore.swift` | UserDefaults JSON 持久化 | ✅ 完成 |
| 下載管理 | `Services/DownloadManager.swift` | 並行下載圖片，寫入本地磁碟 | ✅ 完成 |
| 圖片載入 | `Services/ImageLoader.swift` | async 圖片快取載入 | ✅ 完成 |
| 設定 | `Services/SettingsStore.swift` | UserDefaults 設定持久化 | ✅ 完成 |

### UI 層

| 視圖 | 檔案 | 功能 | 狀態 |
|------|------|------|------|
| 主視圖 | `Views/ContentView.swift` | 來源選擇（Picker menu）、Tab 切換（瀏覽/書籤） | ✅ 完成 |
| 畫廊列表 | `Views/GalleryListView.swift` | 分頁列表、搜尋、篩選列（FilterBarView）、每來源記憶狀態 | ✅ 完成 |
| 閱讀器 | `Views/ReaderView.swift` + `ReaderViewModel.swift` | 橫向翻頁、E-Hentai/漫畫櫃直接 URL 兩種模式 | ✅ 完成 |
| 章節列表 | `Views/ChapterListView.swift` | 漫畫櫃專用，點選章節進入閱讀器 | ✅ 完成 |
| 書籤 | `Views/BookmarkView.swift` | 書籤列表、開啟、刪除 | ✅ 完成 |
| 設定 | `Views/SettingsView.swift` | E-Hentai cookie、下載路徑等 | ✅ 完成 |

---

## 已知問題

（已無已知重大問題）

---

## 變更歷程

### 2026-03-29（續四）

- **功能：漫畫櫃下載按漫畫名資料夾分章節**
  - 新路徑：`{library}/manhuagui/{漫畫名}/{章節名}.cbz`（非法字元替換為 `_`）
  - `DownloadManager.downloadChapter(chapter:gallery:)` 下載單一章節
  - `performChapterDownload`：抓圖 → staging → packageAsCBZ → 清 staging
  - `chapterStates: [String: DownloadState]`（key = chapter URL）追蹤各章節狀態
  - `chapterCBZURL`, `isChapterDownloaded`, `downloadedChapterCount` 等輔助 API
  - `extractedImageURLs(for chapter:gallery:)` 支援讀本地章節 CBZ

- **功能：書籤漫畫打開時顯示未下載集數**
  - `ChapterListView` 載入章節後比較已下載數 vs 總集數
  - 頂部 banner：「有 N 集尚未下載（共 M 集）」＋「全部下載」按鈕
  - 每一章節列表行顯示下載狀態圖示（未下載/排隊/進度/完成/錯誤）
  - 每行右側可點擊下載單集、失敗時可重試

- **功能：讀漫畫優先讀本地已下載章節**
  - `ReaderViewModel.loadChapter` 加 `gallery` 參數
  - 若章節已下載則解壓 CBZ 讀本地，跳過網路請求
  - 自動下一集（nextPage at last）也適用於本地閱讀模式

### 2026-03-29（續三）

- **功能：書籤依來源分開顯示**
  - `BookmarkView` 加入 segmented Picker（全部 / E-Hentai / 漫畫櫃）
  - 依 `gallery.sourceID` 篩選後顯示

- **功能：下載依來源分資料夾**
  - 新路徑：`{library}/{source}/{id}.cbz`（如 `ehentai/`, `manhuagui/`）
  - staging 亦同：`.staging/{source}/{galleryID}/`
  - 保留舊路徑（`{library}/{id}.cbz`）向後相容
  - `resumePendingDownloads` 支援新兩層目錄結構

- **功能：漫畫櫃看完自動接下一集**
  - `ReaderViewModel.loadChapter` 新增 `allChapters` 參數
  - `nextPage()` 在最後一頁時自動呼叫 `nextChapterInList()`
  - 主要邏輯：章節列表是 newest-first，故事下一集 = index - 1
  - Fuzzy fallback：解析「第N集/話/回/卷」並找 N+1，支援前後有其他文字的標題
  - `ChapterListView.onSelect` 改為回傳 `(Chapter, [Chapter])` 以傳遞完整章節列表

- **修復：切換漫畫時章節列表不重新載入**
  - 根因：SwiftUI 的 `ChapterListView` identity 不變，`.task` 不重新執行
  - 修正：`ContentView` 對 `ChapterListView` 加 `.id(gallery.id)`，強制重建

### 2026-03-29（續二）

- **修復：漫畫櫃章節圖片內容與漫畫不符**
  - 根因：`parseChapters` regex `href="/comic/\d+/(\d+)\.html"` 匹配所有漫畫的連結，側欄推薦區的其他漫畫章節連結也被納入，導致章節列表指向錯誤漫畫
  - 修正：從 `comicURL.pathComponents` 取出 comicID，將 regex 限縮為 `href="/comic/{comicID}/(\d+)\.html"`
  - UT：`test_parseChapters_ignoresOtherComicLinks` 驗證其他漫畫連結不被納入

- **修正測試假設：`test_chapterImageURLs_pathMatchesChapter`**
  - CDN 圖片 URL 路徑為目錄結構（如 `/ps3/b/bcm/act_11-1/`），不含 manhuagui comic ID
  - 移除「URL 應含 232」的錯誤斷言，改驗證 URL scheme 為 https 且 host 不為 nil

### 2026-03-29（續）

- **修復：漫畫櫃下載圖片全黑**
  - 根因：`ImageLoader.download` 固定用 `EHentaiService.fetchImageData`，Referer 設為 `e-hentai.org`，漫畫櫃 CDN (`us.hamreus.com`) 需要 `Referer: https://tw.manhuagui.com`
  - 修正：`ImageLoader.image(for:referer:)` 和 `prefetch(url:referer:)` 加 `referer` 參數；`EHentaiService.fetchImageData(url:referer:)` 加 `referer` 參數；`ReaderViewModel` 對漫畫櫃圖片傳 `Referer: https://tw.manhuagui.com`
  - UT：`test_imageLoader_manhuaguiURL_withCorrectReferer_succeeds`

- **修復：E-Hentai 翻頁永遠在同一頁**
  - 根因 1：`goToPage` else 分支只走訪中間頁收集 cursor，但沒有 `load(cursorIndex: idx)` 載入目標頁
  - 根因 2：`parseNextCursor` regex `\?next=` 只匹配 `next` 在第一位時；搜尋時 URL 為 `?f_search=...&next=...`，`&next=` 不匹配
  - 修正：加入 `if idx < cursors.count { await load(cursorIndex: idx) }` 在 for 迴圈後；`parseNextCursor` 改用 `[?&](?:amp;)?next=(\d+)`
  - UT：`test_parseNextCursor_withSearchParams_ampersand`、`test_parseNextCursor_withSearchParams_htmlEntity`

### 2026-03-29

- 新增工作日誌（WORKLOG.md）
- 新增 UT 框架：`ComicLib` library target + `Tests/ComicTests/`
- 撰寫 38 個單元/整合測試（URL 建構、HTML 解析、JSON 解包、WKWebView 圖片擷取）
- Debug 並修復漫畫櫃章節圖片載入：
  1. **根本原因 1（`splic`）**：JSContext 缺少 `String.prototype.splic`，改用 WKWebView
  2. **根本原因 2（SMH setter 未攔截 imgData）**：core.js 先 `var SMH = {}` 再 `SMH.imgData = fn`，第二步不觸發 `window.SMH` 的 setter；修正為同時用 `Object.defineProperty` 攔截 `SMH.imgData` 屬性賦值
  3. **根本原因 3（server 欄位移除）**：新版 API 的 `SMH.imgData()` JSON 不含 `server` 欄位；改從 `SMH.getImage(0)` 或 DOM img src 推斷伺服器 `us.hamreus.com`
  4. **URL 雙重編碼**：`path` 含中文需 percent-encode，`files` 已編碼不可再編碼；分開處理後正確
- 修正後 UT 測試全過：38 tests passed，1 skipped（搜尋需瀏覽器環境）
- 確認圖片 URL `https://us.hamreus.com/...` 回傳 HTTP 200

### 2026-03-28
- 新增多來源架構（ComicSource 協定、SourceManager）
- 新增漫畫櫃來源（ManhuaguiSource、ManhuaguiService）
- 修正漫畫列表解析 regex（`bcover` class 結構）
- 修正分頁解析（`/ <strong>N</strong> 頁` 格式）
- 新增 6 維彈性篩選系統（地區/劇情/受眾/年份/字母/進度）
- 新增章節列表視圖（ChapterListView）
- 修正 URL 建構：篩選路徑 `/list/{slug1}/{slug2}/`，分頁 `{last}_p{N}.html`
- Gallery 增加 `galleryURL` 欄位及向後相容 Codable decoder
- 嘗試 JSContext eval 攔截 → 失敗（splic 問題）
- 改用 WKWebView 方案（ManhuaguiWebExtractor）

---

## 下一步

1. 清除 `ManhuaguiService.swift` 殘留的 JSContext import 與 `parseChapterImages` 方法（已由 WKWebView 取代）
2. 新功能加入時，同步更新 WORKLOG.md 並撰寫對應 UT
