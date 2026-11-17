# ROB RUN 繁體中文化

把 [ROB RUN](https://store.steampowered.com/) 的介面、任務、道具、地名、提示等文字換成**繁體中文（臺灣用語）**，並補上能顯示中文的字型。

> **本專案不含任何遊戲檔案。** 安裝時，程式會讀取你電腦上已安裝的遊戲原版資源，在你自己的電腦上產生中文化檔案。

## 下載與安裝（一般玩家）

1. 到 [Releases](../../releases) 下載最新的 `ROBRUN_繁體中文化_vX.Y.Z.zip`（附 Python 套件離線安裝檔；第一次安裝仍需連網下載 Python 本體，約 10 MB）
2. **完全退出遊戲**（工作管理員裡也不能有 `ROB RUN.exe`）
3. 解壓縮，按兩下 **`一鍵安裝.bat`**
4. 進遊戲：**設定 → 其它 → 語言 → 選「繁體中文」→ 確定**

要回到原版：按兩下 **`解除安裝.bat`**。

詳細說明見 [`使用說明.txt`](使用說明.txt)。

### 系統需求

- Windows 10 / 11（64 位元）
- 遊戲版本 0.7（遊戲大改版後可能需要更新翻譯資料）
- 第一次安裝約需 300 MB 暫存空間（放在 `%LOCALAPPDATA%\ROBRUN_zhTW`，解除安裝時會一併清掉）

## 運作方式

```
你的遊戲原版檔案 ──► patcher/patch.py ──► *_zht.bundle（新檔名，放進遊戲資料夾）
                       ▲        ▲
         data/zh-TW.json   data/glyphs/（繁體字形）
```

1. `install.ps1` 在 `%LOCALAPPDATA%\ROBRUN_zhTW\python` 準備一個**專用的 Python**（不影響系統上的 Python）。
   - Python 本體從 python.org 下載；Release 包附有 `wheels/` 套件離線安裝檔，直接從原始碼安裝時則從 PyPI 下載。
2. `patcher/patch.py` 讀取遊戲 `StreamingAssets\aa\StandaloneWindows64` 裡的 8 個原版 bundle：
   - **字串表**：把「俄語」那一欄的文字換成 `data/zh-TW.json` 的翻譯（依字串 ID 對應）；
   - **語言名稱**：選單裡的那一欄改顯示「繁體中文」；
   - **字型**：在 `TT_Bluescreens SDF` 與 `RobotoBoldCondensed` 的字型貼圖上方接上 `data/glyphs/` 的繁體字形（SDF 格式），並登錄到字元表。
3. 產生的檔案以 `*_zht.bundle` 新檔名放進遊戲資料夾，**原版檔案一個位元組都不改**；再改寫使用者資料夾裡的 Addressables 快取 catalog，讓遊戲改讀新檔名。
4. 安裝完逐項核對；解除安裝會刪掉 `*_zht.bundle` 並從原版重建快取 catalog。

遊戲更新後如果出現新的文字，產生器會保留原文並在安裝訊息裡顯示「還沒有翻譯」的條數。

## 專案結構

| 路徑 | 內容 |
|---|---|
| `一鍵安裝.bat` / `解除安裝.bat` | 玩家用的入口 |
| `install.ps1` / `uninstall.ps1` / `scripts/common.ps1` | 安裝／解除安裝流程 |
| `patcher/patch.py` | 補丁產生器（UnityPy） |
| `patcher/requirements.txt` | 產生器的相依套件 |
| `data/zh-TW.json` | 翻譯文字（從遊戲英文原文直接翻譯），依字串表名稱與字串 ID 對應 |
| `data/glyphs/` | 預先產生的繁體字形（Noto Sans CJK TC，SDF）與授權 |
| `tools/build_glyphs.py` | （開發用）重新產生字形資料 |

## 參與翻譯

翻譯都在 `data/zh-TW.json`：

```json
"tables": {
  "StaticStrings": { "<字串 ID>": "繁體中文翻譯", ... },
  "RealmNames": { ... },
  "TimeFormatterAbbreviations": { ... }
}
```

- 保留 `{0}`、`{size}`、`<color=...>`、`</color>` 這類標記，不要翻譯或刪掉。
- 如果新加的翻譯用到字形資料裡沒有的字，執行 `tools/build_glyphs.py` 重新產生字形（需要 Noto Sans CJK 字型檔，詳見檔案開頭說明）。

## 常見問題

- **黑畫面／閃退／進不去**：先按兩下 `解除安裝.bat` 回到原版，確認遊戲本身正常。
- **裝了沒有中文**：確認語言選的是「繁體中文」，再看安裝訊息有沒有 `[失敗]`。
- **詳細記錄**：`%LOCALAPPDATA%\ROBRUN_zhTW\log.txt`、`patch_report.json`

## 注意事項與免責聲明

- 這是玩家自製的非官方中文化，與遊戲開發商 Kefir 無關。
- 本工具會讓遊戲讀取修改過的資源檔。ROB RUN 是有反作弊的線上遊戲，**使用風險請自行承擔**。若官方表示不允許，請停止使用。
- 遊戲名稱、商標與遊戲內容的版權屬於其權利人；本專案不散佈任何遊戲檔案。

## 授權與致謝

- **程式碼**（安裝腳本、`patcher/`、`tools/`）：MIT，見 [`LICENSE`](LICENSE)
- **字形資料**（`data/glyphs/`）：由 Noto Sans CJK TC 衍生，依 [SIL Open Font License 1.1](data/glyphs/OFL.txt) 授權
- **翻譯文字**（`data/zh-TW.json`）：本專案從遊戲英文原文直接翻譯，以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 釋出；遊戲原文的權利屬於 Kefir
- bundle 讀寫使用 [UnityPy](https://github.com/K0lb3/UnityPy)
