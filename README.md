# kehao-claude-skills

Kehao 個人的 [Claude Code](https://code.claude.com) plugin marketplace —— 集中管理、版控、跨機器同步自己的 skills 與工具,並可分享給他人。

## 內容

| Plugin | 說明 | Skills |
|---|---|---|
| `kehao-util` | 日常工具集 | `new-skill`(從樣板長出新的 skill) |

## 安裝

```text
/plugin marketplace add kehao/kehao-claude-skills      # 或本機路徑:~/projects/kehao-claude-skills
/plugin install kehao-util@kehao-claude-skills
```

安裝後,plugin 內的 skill **一律 namespaced**,例如:

```text
/kehao-util:new-skill <name> "<description>" [plugin]
```

> 內容更新後,使用者用 `/plugin marketplace update` 刷新(發布前記得 bump version,見下)。

## 開發

最順的開發迴圈是用 `--plugin-dir` 直接載入、`/reload-plugins` 熱更新,不必每次 reinstall:

```bash
claude --plugin-dir ./plugins/kehao-util
# 在 Claude Code 內:
/kehao-util:new-skill demo-skill "Scaffold a demo skill"
/reload-plugins         # 改了內容後熱載入
```

驗證(本機,離線可跑):

```bash
./scripts/validate.sh   # 內含 claude plugin validate --strict + 一致性檢查
```

## 新增一個 skill

```text
/kehao-util:new-skill my-new-skill "一句話說明這個 skill 做什麼"
```

`new-skill` 會在 **目前 repo** 的 `plugins/<plugin>/skills/<name>/SKILL.md` 產生骨架(從 `templates/SKILL.md.tmpl`),不會覆蓋既有 skill,且只在 marketplace repo root 執行。產生後把 `SKILL.md` 的 TODO 換成真正的指引即可。

## 版本策略

- marketplace entry 與該 plugin 的 `plugin.json` 的 `version` 要**一致**。
- **每次要讓使用者收到更新前,務必 bump version**(version 沒變使用者不會收到更新)。
- 發版用 `claude plugin tag plugins/<plugin>`(會驗證兩邊版本一致並打 git tag)。

## 結構

```
.claude-plugin/marketplace.json     # marketplace 清單
plugins/<plugin>/
  .claude-plugin/plugin.json        # plugin metadata
  skills/<skill>/SKILL.md           # 每個 skill
scripts/validate.sh                 # 驗證
```

## 授權

MIT — 見 [LICENSE](./LICENSE)。
