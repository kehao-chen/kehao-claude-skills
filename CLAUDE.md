# CLAUDE.md

本 repo 是一個 **Claude Code plugin marketplace**(`kehao-claude-skills`)。給 Claude 在此 repo 工作時的指引。

## 這是什麼

- `.claude-plugin/marketplace.json` —— marketplace 清單(列出各 plugin)。
- `plugins/<plugin>/.claude-plugin/plugin.json` —— 每個 plugin 的 metadata。
- `plugins/<plugin>/skills/<skill>/SKILL.md` —— 每個 skill。
- `scripts/validate.sh` —— 提交前的驗證。

> 官方規範:`commands/ agents/ skills/ hooks/` 一律放在 **plugin root**,不要放進 `.claude-plugin/`(裡面只放 `plugin.json`)。

## 新增 skill 的標準流程

1. `/kehao-util:new-skill <name> "<description>" [plugin]`(預設 plugin = `kehao-util`)。
   - 名稱用 kebab-case;skill 從 `templates/SKILL.md.tmpl` 產生,不覆蓋既有。
2. 編輯產生的 `SKILL.md`,把 TODO 換成真正的指引。
3. 跑 `./scripts/validate.sh`。
4. 開發中用 `/reload-plugins` 熱載入測試;對外發布前 bump version。

## 版本策略(重要)

- marketplace entry 與該 plugin `plugin.json` 的 `version` 必須**一致**。
- **要讓使用者收到更新前一定要 bump version**(沒變更不會推送更新;省略 version 則以 git commit SHA 計)。
- 發版:`claude plugin tag plugins/<plugin>`(驗證版本一致並打 `{name}--v{version}` tag)。

## 開發/測試

```bash
claude --plugin-dir ./plugins/kehao-util   # 載入,不必 install
# /kehao-util:<skill> ... ; 改完 /reload-plugins
./scripts/validate.sh                       # claude plugin validate --strict + 一致性檢查
```

## 慣例

- 命名:plugin、skill 皆 kebab-case;skill 呼叫一律 namespaced `/<plugin>:<skill>`。
- 文件(README、本檔、註解)優先**臺灣正體中文**;程式碼與識別字維持英文。
- 提交前務必 `./scripts/validate.sh` 通過。
