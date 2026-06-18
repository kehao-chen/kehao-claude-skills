# kehao-claude-skills

我(Kehao)自己在用的一包 [Claude Code](https://code.claude.com) skills 與小工具,整理成一個 plugin marketplace,順手公開分享。

> ⚠️ **個人自用、原樣分享。** 這純粹是我自己用得爽的東西,丟出來只是分享 ——
> **不保證維護、不保證更新、也不保證適合你**。覺得有用就拿去、改成你自己的版本。

## 有哪些

### `english-coach` — 背景英文教練
每次我手打英文送出,它在背景默默檢查,有問題才在狀態列底部丟**一行**建議,例如:

```
😇 I has finish → I have finished (verb form)
😇 revert back to you → get back to you (more natural)
```

除了文法,也會教更像母語者(美式)的講法。**不進 AI 的對話、不加 token、不卡你的輸入**;貼上的程式碼、log、中文、太長的內容都會自動略過,URL/路徑會被遮掉不外送。後端走 Groq(快又便宜)。

### `kehao-util` — 日常小工具

| Skill | 做什麼 |
|---|---|
| `new-skill` | 一行指令從樣板長出新的 skill 骨架(我用它來長這個 repo 的下一個 skill) |

## 想試試看

```text
/plugin marketplace add <github-user>/kehao-claude-skills   # 公開後;目前我是本機 ~/projects/kehao-claude-skills
/plugin install english-coach@kehao-claude-skills           # 或 kehao-util@kehao-claude-skills
```

- **english-coach**:裝完跑一次 `/english-coach:setup` 接上狀態列,並在 `~/.claude/english-coach/secrets.env` 放你的 Groq API key,開新 session 就會動。設定細節見 [plugin README](./plugins/english-coach/README.md)。
- **kehao-util**:裝完直接 `/kehao-util:new-skill <name> "<說明>"`。

> 注意:plugin 內的 skill 一律 namespaced,所以是 `/english-coach:setup`、`/kehao-util:new-skill`。

## 授權

MIT —— 拿去用、改、散布都行,自負風險(見 [LICENSE](./LICENSE))。
