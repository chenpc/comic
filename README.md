# Comic 漫畫閱讀器

macOS 原生漫畫閱讀器，支援多個中文漫畫來源與離線閱讀。

## 功能

### 漫畫來源
| 來源 | 類型 | 說明 |
|------|------|------|
| [無敵漫畫（8comic）](https://www.8comic.com) | 章節制 | 支援動態混淆 JS 解析 |
| [漫畫櫃（manhuagui）](https://tw.manhuagui.com) | 章節制 | 繁體中文漫畫 |
| [漫畫人（manhuaren）](https://www.manhuaren.com) | 章節制 | 簡體中文漫畫 |
| [E-Hentai](https://e-hentai.org) | 圖庫制 | 同人誌、漫畫圖庫 |

### 主要功能
- **瀏覽 / 搜尋** — 依分類、地區篩選，支援關鍵字搜尋
- **書籤** — 收藏漫畫，顯示下載狀態
- **下載** — 將章節下載為 CBZ 格式，支援批次全部下載
- **Library 離線模式** — 瀏覽本地已下載的 CBZ 漫畫，無需網路
- **繼續閱讀** — 記錄閱讀進度，章節列表顯示上次讀到的位置
- **iCloud 同步** — 書籤與閱讀紀錄透過 iCloud Drive 跨裝置同步
- **圖片快取** — 磁碟快取加速重複閱讀，可手動清除
- **全螢幕模式** — 進入全螢幕後隱藏所有 UI，沉浸閱讀
- **右鍵複製連結** — 在漫畫或章節上右鍵可複製原始 URL

### 操作方式
| 動作 | 快捷鍵 |
|------|--------|
| 下一頁 | `→` / `Space` |
| 上一頁 | `←` |
| 跳頁 | 點擊頁碼按鈕 |
| 全螢幕 | `⌃⌘F` |

## 系統需求

- macOS 14 (Sonoma) 以上

## 安裝

從 [Releases](https://github.com/chenpc/comic/releases) 下載最新的 `Comic.pkg`，執行後依照指示安裝，應用程式將安裝至 `/Applications/Comic.app`。

## 從原始碼建置

需要 Xcode 15 以上，或安裝 Swift 5.9 工具鏈。

```bash
git clone https://github.com/chenpc/comic.git
cd comic
swift build -c release
.build/release/Comic
```

執行測試：

```bash
swift test
```

## Library 離線模式設定

1. 前往「設定」→「Comic Library」選擇本地資料夾
2. 在書籤頁面點擊下載圖示，章節將儲存為 CBZ 格式
3. 下載完成後可在「Library」分頁離線瀏覽

目錄結構：

```
Library/
├── eightcomic/
│   └── 漫畫名稱/
│       ├── 第001話.cbz
│       └── 第002話.cbz
├── manhuagui/
│   └── 漫畫名稱/
│       └── ...
└── ehentai/
    └── {gallery_id}.cbz
```

## iCloud 同步

書籤與閱讀紀錄可透過 iCloud Drive 跨裝置同步。啟用前請確認：

1. 系統設定 → Apple ID → iCloud → 開啟 iCloud Drive
2. 在 App「設定」→「iCloud 同步」開啟開關

同步資料存放於 `iCloud Drive / Comic /`。

## 授權

MIT License
