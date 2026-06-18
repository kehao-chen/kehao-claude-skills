# kehao-claude-skills

個人自用的 [Claude Code](https://code.claude.com) skills 與小工具，做成一個 plugin marketplace。

> 這些是我平常自己在用的東西，放上來給有需要的人參考——沒有維護計畫，歡迎直接拿去改成你自己的版本 🙂

## 有哪些

### `english-coach`——背景英文教練

有趣的點不在「會檢查英文」，而在**它完全不碰 AI 的工作**。你手打英文送出，它在背景看一眼，有問題才在狀態列底部丟**一行**建議：

```text
😇 I has finish → I have finished (verb form)
😇 revert back to you → get back to you (more natural)
```

除了文法，也會點出更像美國人會講的說法。這些建議**只給你看**：不進 AI 的對話、不花一個 token、也不會讓你的輸入慢半拍。貼上的程式碼、log、中文、太長的內容自動略過，URL 和路徑先遮掉再送出。後端用 Groq，所以反應快。

### `kehao-util`——雜項小工具

| Skill | 做什麼 |
|---|---|
| `new-skill` | 從樣板長出一個新 skill 的骨架——我就是用它來長這個 repo 裡的下一個 skill |

## 想試試看

在 Claude Code 裡兩行就裝好：

```text
/plugin marketplace add kehao-chen/kehao-claude-skills
/plugin install english-coach@kehao-claude-skills      # 或 kehao-util@kehao-claude-skills
```

- **english-coach**：再跑一次 `/english-coach:setup` 接上狀態列，把 Groq API key 放進 `~/.claude/english-coach/secrets.env`，開新 session 就會動——細節見 [它自己的 README](./plugins/english-coach/README.md)。
- **kehao-util**：`/kehao-util:new-skill <name> "<說明>"`。

> plugin 裡的 skill 都帶 namespace，所以前面要加 plugin 名：`/english-coach:setup`、`/kehao-util:new-skill`。

## 授權

MIT——自由使用、修改、散布（見 [LICENSE](./LICENSE)）。
