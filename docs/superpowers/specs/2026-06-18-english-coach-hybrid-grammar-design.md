# english-coach 混用本地文法（Harper）+ LLM 語感——設計

- 日期：2026-06-18
- 狀態：草案，待 review
- 範圍：`plugins/english-coach`
- 相關：靈感工具現況見該 plugin 之 `README.md` 與 `lib/`

## 1. 背景與目標

現在 english-coach 把**文法錯誤**與 **native-American 語感／idiom** 兩件事**全交給一個遠端 LLM**（`lib/prompt-template.txt` 同時做兩者）。問題：每則合格的手打英文都要打一次網路，慢、需要 API、且把使用者原文送出去。

目標是**混用**：

- 用 **Harper**（離線、Rust 單檔 CLI）在**本地**擋掉機械性的文法／拼字錯。
- LLM **只**留下它不可取代的部分——語感／idiom／搭配／簡潔（「講得像美國人」）。
- 三個收益：**速度**（本地 ~ms）、**隱私**（有錯的句子根本不出網路）、**品質**（LLM 專心做它最強的語感）。

不改變對外行為的兩個鐵則：**不進 Claude context、不加 token、不卡輸入**；statusline 仍是**單行** `😇 original → improved (reason)`。

## 2. 現況（簡述）

- `UserPromptSubmit` hook → `lib/check.sh`：recursion guard → `ec_json_get` 取 prompt/session_id → `ec_seq_bump`（每次送出遞增 seq，舊 tip 自動失效）→ `ec_redact`（URL/path 換成 `(url)`/`(path)`）→ `ec_should_skip`（擋 code/log/CJK/太短太長/多行/指令/高符號比）→ 把 prompt 寫進 600 暫存檔 → 背景 `nohup` 丟給 `lib/worker.sh`。
- `lib/worker.sh`：`ec_run_provider`（`EC_BACKEND` = claude-cli|anthropic|openai 之 dispatch）拿 LLM 原始輸出 → `ec_sanitize_tip`（格式白名單＋剝控制字元＋no-op guard＋長度上限）→ seq guard → `ec_atomic_write` 到 tips 目錄。
- `lib/statusline.sh`：跑內層 statusline → 若 tip 的 `seq` 對得上當前 session 才附加顯示。

## 3. 既定決策（已與使用者確認）

| 決策 | 結論 |
|---|---|
| 組合方式 | **文法優先、gate 住 LLM**：本地有硬錯誤就顯示且**不**呼叫 LLM；乾淨才呼叫 LLM 做純 idiom |
| 本地引擎 | **只用 Harper**，**放棄 LanguageTool**（連同 JVM/server、`EC_LT_URL`、HTTP adapter 全不做） |
| Harper 可選 | `EC_GRAMMAR=auto\|harper\|off`，**預設 `auto`**（裝了就用、沒裝退回今天行為） |
| `WordChoice`/`Redundancy` 等「介於文法與語感」 | **歸語感、丟 LLM**；gate 只認硬錯誤 |
| 缺字／多字（Insert/Remove，如漏冠詞介係詞） | **v1 就本地渲染**（span + perl 字元切片）；ReplaceWith 為其平凡子集 |
| 全本地 idiom（Ollama） | **只寫文件**，不綁核心 |

## 4. 架構

### 4.1 控制流（`check.sh` 不動，分支集中在 `worker.sh`）

`check.sh` 維持原樣（含「不卡輸入」的背景 `nohup` 派工）。Harper 在 **worker** 裡跑——本地 ~ms，且在背景，不影響輸入。

```
worker_main(sid_key, seq, pf):
  state = "unavailable"; tip = ""

  if ec_grammar_resolve() == harper:        # EC_GRAMMAR + command -v $EC_HARPER_BIN
      tip = ec_grammar_check(pf); rc = $?
      # 三態（注意：harper 找到 lint 會「先印 JSON、再以非零退出」，
      # 所以成敗一律看 stdout 能否解析成 JSON，絕不看 exit code）：
      if   rc == 0 and tip != "": state = "hard_tip"        # 已驗出硬錯誤
      elif rc == 0:               state = "verified_clean"  # 成功解析、無硬錯誤候選
      else:                       state = "unavailable"     # 無 JSON/解析失敗/執行錯誤

  if state != "hard_tip":                   # 沒有要顯示的本地硬錯誤 → 走 LLM
      tmpl = (state == "verified_clean") ? "prompt-template-idiom.txt"
                                         : "prompt-template.txt"   # combined（含 unavailable）
      tip = ec_sanitize_tip( ec_run_provider(pf, tmpl) )          # provider 從 tmpl 讀 rubric

  # 之後與現狀相同：
  if ec_seq_current(sid_key) != seq: return    # seq guard
  atomic_write(tips/<sid_key>, "seq=<seq>\n<tip>")
```

關鍵：**有硬錯誤的句子永遠不進入 `ec_run_provider`**——這就是隱私與速度的來源。

### 4.2 元件清單

| 檔案 | 變動 | 內容 |
|---|---|---|
| `lib/check.sh` | 不變 | 維持薄派工、不阻塞 |
| `lib/worker.sh` | 改 | 上面的分支邏輯；選 prompt template |
| `lib/grammar.sh` | **新增** | `ec_grammar_resolve`、`ec_grammar_check`、`ec_map_lint` |
| `lib/config.sh` | 加 | `EC_GRAMMAR`、`EC_HARPER_BIN`、`EC_HARPER_DIALECT`、`EC_HARPER_GATE` |
| `lib/prompt-template.txt` | 不變 | combined（fallback：Harper off/不在時用，＝今天行為） |
| `lib/prompt-template-idiom.txt` | **新增** | idiom-only（Harper 已查過文法時用） |
| `README.md` | 改 | grammar 層說明、安裝、設定、隱私 |
| `skills/setup/SKILL.md` | 小改 | 提一句 Harper 為選配 |
| `tests/`（或 `scripts/test-grammar.sh`） | **新增** | 見 §9 |
| `plugin.json` + `marketplace.json` | 版本 | `0.1.0` → `0.2.0`（一致） |

## 5. `lib/grammar.sh`（新模組）

### 5.1 `ec_grammar_resolve` → echo `harper` 或 `off`

- `EC_GRAMMAR=off` → `off`。
- `EC_GRAMMAR=harper` → 若 `command -v "$EC_HARPER_BIN"` 有 → `harper`；否則記 log（§8）後 `off`。
- `EC_GRAMMAR=auto`（預設）→ 有 binary 就 `harper`，否則 `off`（安靜）。

### 5.2 `ec_grammar_check <textfile>` → echo 一行 `😇 …` 或空

呼叫：

```sh
"$EC_HARPER_BIN" lint --format json --quiet --no-color \
  -d "${EC_HARPER_DIALECT:-us}" "$textfile"
```

- 輸入用 **temp 檔路徑**（`check.sh` 已寫好的 `.txt`），避免 stdin 與「位置參數是文字還是路徑」的歧義；`.txt` 副檔名讓 Harper 以 plaintext 自動辨識。檔內已是 redact 過的 prose。
- 輸出是 **JSON 陣列**；我們只取 `.[0].lints`（我們只送一個輸入）。
- ⚠️ **exit code 不可信**：`harper-cli lint --format json` 會**先把 JSON 印到 stdout，再於「有 lint」時 `bail!("Lints were found")` 以非零退出**（upstream `harper-cli/src/lint.rs`：JSON 印出 L365-367、`if has_lints { bail }` L374-376）。「找到錯誤」本身就是非零退出，因此 **成敗一律以「stdout 能否解析成預期 JSON」判定，完全忽略 exit code**。
- 用 `jq` 解析 `.[0].lints`，回傳三態給 worker（§4.1／§8）：解析成功且有硬錯誤候選 → echo 該行、`return 0`（hard_tip）；解析成功但無硬錯誤候選 → echo 空、`return 0`（verified_clean）；**stdout 無法解析（空／壞 JSON／執行錯誤）→ `return` 非零（unavailable）**。Harper CLI 為 experimental、欄位會漂，**任何意外都不可炸掉、不可阻斷**。

### 5.3 選擇政策（哪一條、要不要 gate）

每條 lint 的 `kind` 分兩桶：

- **硬錯誤（gate；Harper 顯示、跳過 LLM）**：
  `Spelling, Typo, Grammar, Agreement, Capitalization, Punctuation, Usage, Malapropism, BoundaryError, Eggcorn, Nonstandard`
- **語感／風格（不 gate；落到 LLM）**：
  `Style, Readability, Repetition, Redundancy, WordChoice, Enhancement, Regionalism, Miscellaneous, Formatting`

規則：

1. `EC_HARPER_GATE=errors`（預設）：只在「硬錯誤」桶裡挑。`any`：所有 `kind` 都可挑（Harper 找到什麼就顯示什麼）。
2. 在候選裡取 **`char_start` 最小**那條（修最前面的錯）；平手用 **`priority` 最小**（Harper 內部 lower=higher priority）。
3. 候選為空（只剩風格類，或完全無錯）→ echo 空、`return 0`（verified_clean）→ worker 走 idiom-only LLM。

> Harper 的 `kind` 全集（供對照）：Agreement, BoundaryError, Capitalization, Eggcorn, Enhancement, Formatting, Grammar, Malapropism, Miscellaneous, Nonstandard, Punctuation, Readability, Redundancy, Regionalism, Repetition, Spelling, Style, Typo, Usage, WordChoice。未列入硬錯誤桶者一律視為語感／風格。

### 5.4 `ec_map_lint`：一條 lint → `😇 original → improved (reason)`

統一用 **span + 全文套用 suggestion** 的方式，對 Replace/Insert/Remove 一致處理：

1. 取全文 `T`（從 temp 檔讀），lint 的 `span{char_start,char_end}`（**字元**索引、半開區間），與 `suggestions[0]`。
2. `suggestions[0]` 是 `Display` 字串，先判種類（注意是**彎引號** U+201C/U+201D，也容忍 ASCII 引號）：
   - `Replace with: "X"` → 在 `[char_start,char_end)` 換成 `X`。
   - `Insert "X"` → 在 `char_end` 後插入 `X`（必要時補一個空白）。
   - `Remove error` → 刪掉 `[char_start,char_end)`。
   - 其他／無 suggestion → 此 lint 不可渲染，跳過換下一條候選；都不可渲染 → echo 空（落 LLM）。
3. 以 perl（`-CSDA`，字元安全）算出 `corrected` 全文，再對 `T` 與 `corrected` 取**字元層級**最長共同前綴／後綴、向兩側擴到**詞邊界**，中間那段即：
   - `original` = `T` 的該段（缺字情形可能為空，改取插入點鄰近詞當視窗）
   - `improved` = `corrected` 的該段
4. `reason`（決定性推導，英文，與既有 tip 風格一致）：**reason 必須是具體的 WHY，絕不可用裸分類標籤**——這是既有 rubric 的硬規定（`lib/prompt-template.txt:14`「NEVER a bare category label like (article)…」）與 main 最新方向（commit `5747efa`「parenthetical carries the concrete reason, not a category tag」）；Harper 路徑與 LLM 路徑的 UX 必須一致。
   - 令 `m = trim(message)`。Harper 的 `message` 多半已是具體說明 → **優先用 `m`**（截到 ≤48 字；把結尾問號或「Did you mean…?」這類疑問句式轉成陳述）。
   - 僅當 `m` 不堪用時，退到**具體短語**（非裸分類）map，例如：`Spelling`→“possible misspelling”、`Typo`→“likely typo”、`Agreement`→“subject–verb agreement”、`Repetition`→“repeated word”、`Punctuation`→“missing/incorrect punctuation”。**不要**用 “spelling”“grammar”“word choice” 這種桶名。
5. 組成 `😇 <original> → <improved> (<reason>)`，再過共用 sanitizer（§5.5）。

> 平凡子集：ReplaceWith 時 `original=matched_text`、`improved=X`，不必走 diff；可作為快路徑，但 §5.4 的統一法是正規路徑（涵蓋漏／多冠詞、介係詞等對非母語者最常見的錯）。

### 5.5 共用 sanitizer

本地產生的行同樣過一次 `ec_sanitize_tip`（或抽出的共用子集）做 defense-in-depth：剝控制字元、長度上限（`EC_MAX_TIP_LEN`）、no-op guard（箭頭兩側相同則丟棄）。因為行是我們自己組的，格式白名單天然成立。

## 6. LLM prompt：拆兩條

- 保留 `lib/prompt-template.txt`＝**combined**（grammar + idiom）。僅在 `EC_GRAMMAR=off` 或 Harper 不在時使用 → 完全等同今天行為，**零回歸風險**。
- 新增 `lib/prompt-template-idiom.txt`＝**idiom-only**，要點：
  - 明說「文法／拼字已在本地檢查過，**只**挑 native-American 語感／idiom／自然搭配／簡潔；不要挑小文法」。
  - 同一行輸出格式 `😇 original → improved (reason)`，否則 NOTHING。
  - 一句 soft 安全網：若仍看到**明顯**漏網的文法錯，可指出（避免本地漏抓就完全沒人管）。
- worker 依 §4.1 的 **state** 選 template：`verified_clean` → idiom-only；其餘（`unavailable`：off／Harper 不在／解析失敗）→ combined。透過既有的 `ec_run_provider`／`ec_rubric` 機制（把 `ec_rubric` 改成可指定 template 檔）。

## 7. 隱私

- gate 後，**被本地驗出硬錯誤的句子完全不出網路**（hard_tip）。其餘才送 LLM：`verified_clean` → idiom-only；`unavailable`（Harper off／不在／解析失敗）→ combined（＝今天，無回歸）。
- 既有保護不變：URL/path 先 redact；金鑰只在 600 的 `secrets.env`、不進 argv、不進對話。
- 文件補一段（不綁核心）：把 `EC_OPENAI_BASE_URL` 指向本地 Ollama（`http://localhost:11434/v1`）即可讓 idiom 也全本地——現有 openai 後端已支援。

## 8. 錯誤處理與退回

三態（見 §4.1）對應的退回：

- **hard_tip**（解析成功、有硬錯誤候選）→ 顯示本地行、**不呼叫 LLM**。注意此時 harper 多半以**非零退出**（找到 lint 即 bail），但因 stdout 有合法 JSON → 視為成功。
- **verified_clean**（解析成功、無硬錯誤候選）→ 走 **idiom-only** LLM（此時「文法確實已驗過且乾淨」的前提才成立）。
- **unavailable**（`EC_GRAMMAR=off`、Harper 不在、或 stdout 無法解析／壞 JSON／執行錯誤）→ 走 **combined** LLM（＝今天的完整 grammar+idiom 覆蓋）。
  - 關鍵修正：解析失敗**不可**降級成 idiom-only——那等於謊稱「文法已查過」，會在 CLI/schema 漂移時把既有覆蓋整個弱化。失敗就回 combined（無回歸）；若使用者偏好，亦可設定成 no-network/no-tip。
- log（沿用 `EC_LOG`，預設關）：resolve 結果、最終 state、harper 退出碼與 stdout 是否可解析，便於除錯；不記原文（除非既有 `EC_LOG_ORIGINAL`）。
- `EC_HARPER_BIN` 可被環境覆寫 → 亦是**測試注入點**（見 §9）。

## 9. 測試

設計重點：`ec_grammar_check` 與 `ec_map_lint` 為**可單測的純函式**（檔入／JSON 入 → 行出）；`EC_HARPER_BIN` 可注入假 harper（吐罐頭 JSON），provider 可用既有 `EC_BACKEND` stub。

新增 `plugins/english-coach/tests/`（或 `scripts/test-grammar.sh`），用簡單 bash 斷言涵蓋：

1. ReplaceWith 拼字（`beleive`）→ `😇 beleive → believe (possible misspelling)`（reason 為具體短語、非裸分類）。
2. Agreement（`are`→`is`）→ 正確一行。
3. Insert（漏冠詞）→ 正確渲染 `original → improved`。
4. Remove（多餘字）→ 正確渲染。
5. 只有風格類 lint + `EC_HARPER_GATE=errors` → `ec_grammar_check` 回空（worker 會走 LLM）。
6. `EC_HARPER_GATE=any` → 風格類也顯示。
7. Harper 不在 + `EC_GRAMMAR=auto` → resolve=off → 走 combined。
8. `EC_GRAMMAR=off`（即使裝了 harper）→ 不呼叫 harper。
9. Harper 吐**壞 JSON／空 stdout**（不論 exit code）→ `ec_grammar_check` 回**非零**（unavailable）、不炸 → worker 走 **combined**（不是 idiom-only）。
10. 全乾淨（無 lint）→ echo 空、`return 0`（verified_clean）→ 走 **idiom-only** LLM。
11. **exit-code 回歸測（守住 privacy gate）**：假 harper **輸出含一個 hard error 的合法 JSON、但 `exit 1`** → 必須仍判 hard_tip、顯示本地行、**不呼叫 LLM**（對應 §5.2 的 upstream `bail!` 行為）。
12. **state 不混測**：合法 JSON 無 hard error（verified_clean）→ idiom-only；對照壞 JSON（unavailable）→ combined，確認兩條路不混淆。

並維持 `./scripts/validate.sh` 通過。

## 10. 發版

- `plugin.json` 與 `marketplace.json` 的 `english-coach` 版本 `0.1.0` → **`0.2.0`**（兩處一致；新功能、向後相容）。
- `claude plugin tag plugins/english-coach`。

## 11. 非目標（YAGNI）

- 不支援 LanguageTool（不做 server、`EC_LT_URL`、HTTP adapter）。
- 不做 grammar 引擎的 dispatch table（本地只有一個引擎）。
- 不把 Ollama 設為預設、不自動安裝 Harper。
- 不改 statusline 顯示模型（維持單行）。
- 不在 `check.sh` 做同步文法檢查（維持不阻塞輸入）。

## 12. 風險與緩解

| 風險 | 緩解 |
|---|---|
| Harper CLI experimental、flag／JSON 欄位會漂（如已移除的 `--language`） | pin 預期版本並寫進註解；解析全程防禦式，**成敗看 stdout 是否為合法 JSON、不看 exit code**；解析失敗→unavailable→走 **combined**（不降級成 idiom-only）；升級時重看 `--help` 與 JSON schema |
| `harper-cli` 找到 lint 即以 `bail!` 非零退出，易被誤判為「失敗」而繞過本地、破壞 privacy gate | 判斷成敗只看 stdout 能否解析 JSON、忽略 exit code；測試 11 鎖此回歸 |
| `suggestions` 是 `Display` 字串、彎引號 | 明確剝彎引號（容忍 ASCII）；無法解析的 suggestion 跳過該 lint |
| span 為字元索引、可能含多位元組 | 切片一律用 perl `-CSDA`（字元安全），不用 byte 工具 |
| Harper 冷啟動 ~數十 ms | 在背景 worker 跑，不影響輸入；可接受 |
| 本地漏抓文法 | idiom prompt 的 soft 安全網兜底 |
| 回歸 | `off`／Harper 不在時走原 combined prompt，行為與今天完全一致 |

## 13. 開放問題

無（決策見 §3）。
