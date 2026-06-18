# english-coach (plugin)

每次你**手打英文**送出時,背景檢查你的英文,有問題才在底部狀態列丟一條 `😇 original → corrected (Pattern)`(含 native-American 語感建議)。**不進 Claude 的 context、不加 token、不卡輸入。**

> 這是平常自己在用的小工具,放出來單純分享。沒有特別的維護計畫,歡迎自由取用、改成適合你的版本 🙂

## 兩個部分

| 部分 | 機制 |
|---|---|
| **檢查(hook)** | plugin `UserPromptSubmit` hook,enable 後自動生效 |
| **顯示(statusline)** | plugin 不能設主 statusLine → 跑一次 `/english-coach:setup` 接線 |

## 安裝

```text
/plugin marketplace add kehao/kehao-claude-skills   # 或本機路徑
/plugin install english-coach@kehao-claude-skills
/english-coach:setup          # 一次性,接 statusline
```

接著(若還沒設定):

```bash
# Groq API key(預設後端)
printf 'EC_OPENAI_API_KEY=gsk_xxx\n' > ~/.claude/english-coach/secrets.env
chmod 600 ~/.claude/english-coach/secrets.env
```

開**新的** session,手打一句有錯的英文,底部就會出現提示。

## 設定

放在 `~/.claude/english-coach/config.local.sh`(state 與 secrets 都在這個固定目錄):

```sh
EC_BACKEND=openai
EC_OPENAI_BASE_URL=https://api.groq.com/openai/v1
EC_OPENAI_MODEL=openai/gpt-oss-120b      # alt: openai/gpt-oss-20b(更快) / qwen/qwen3-32b
EC_OPENAI_REASONING_EFFORT=low
EC_OPENAI_MAX_TOKENS=512
EC_TIP_SGR=38;5;248                       # tip 顏色(ANSI SGR)
[ -f "$EC_HOME/secrets.env" ] && . "$EC_HOME/secrets.env" || true
```

可調 skip 門檻(`EC_MAX_WORDS`、`EC_MAX_SENTENCES`、`EC_MIN_WORDS`…)同樣放這裡。

## 移除

```text
/english-coach:teardown       # 還原 statusline
/plugin                       # 把 english-coach 停用 → 移除 hook
```

`config.local.sh` / `secrets.env` / `tips` / `state` 會保留;要全清就手動刪 `~/.claude/english-coach/`。

## 運作細節

- **程式碼**在 plugin(`lib/`,從 `${CLAUDE_PLUGIN_ROOT}` 執行);**狀態/設定/金鑰**在固定的 `~/.claude/english-coach/`(跨 plugin 更新存活,且讓 statusline wrapper 找得到 tip)。
- per-session 單調遞增 `seq` 確保只顯示「對得上當前輸入」的 tip;送下一句舊 tip 自動失效。
- `skiprules` 在呼叫 LLM 前就擋掉程式碼/log/CJK/太短太長;URL/路徑會被遮成 `(url)`/`(path)` 再送(不外洩)。
- 後端走 OpenAI 相容 API(預設 Groq);key 只放 600 的 `secrets.env`,不進 argv、不進對話。
