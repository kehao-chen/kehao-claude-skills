---
name: setup
description: One-time setup for english-coach — wire the statusline so coaching tips appear. Run once after enabling the plugin.
disable-model-invocation: true
---

# english-coach setup — wire the statusline

The english-coach **hook** is active automatically once this plugin is enabled. But Claude Code
plugins cannot set the main statusLine, so the **tip display** must be wired once. Do it now.

## Steps

1. Run the wiring script:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/wire-statusline.sh"
   ```

   It deploys the statusline wrapper to a stable path (`~/.claude/english-coach/`), saves your
   current statusline as the inner one, points `settings.json` at the wrapper, and backs up
   settings first. It is idempotent.

2. Make sure the backend key is present. english-coach uses Groq by default; the user must have
   `~/.claude/english-coach/secrets.env` containing `EC_OPENAI_API_KEY=gsk_...` (chmod 600), and
   `~/.claude/english-coach/config.local.sh` selecting the backend (see the plugin README). If
   `secrets.env` is missing, tell the user to create it before testing.

3. Tell the user:
   - **Open a NEW Claude Code session** for the statusline change to take effect.
   - Type a hand-typed English sentence with a small error to see a `😇 original → corrected (Pattern)`
     tip appear at the bottom.

If `wire-statusline.sh` exits non-zero, report its message and stop.

> 選配：裝 `harper-cli`（`brew install harper`）即啟用本地文法層——有文法錯時本地直接修、不呼叫 LLM。見 README 的「本地文法」段。
