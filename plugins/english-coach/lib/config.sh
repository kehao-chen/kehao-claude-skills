# Sourced by every english-coach script. All values env-overridable.
: "${EC_HOME:=$HOME/.claude/english-coach}"

# Trigger thresholds (skip rules, §6). URLs/paths are redacted (not skipped) by
# ec_redact before counting, so a long hand-typed message with a link still gets coached.
: "${EC_MIN_WORDS:=4}"
: "${EC_MAX_WORDS:=80}"
: "${EC_MAX_SENTENCES:=6}"
: "${EC_SKIP_MULTILINE:=1}"
: "${EC_SYMBOL_RATIO_MAX:=30}"   # percent non-alnum above which we skip

# Output
: "${EC_MAX_TIP_LEN:=120}"
# Tip styling: ANSI SGR params (without the ESC[ prefix / m suffix) applied to the
# statusline tip. Default is a readable-but-subtle gray. Other ideas:
#   2 = dim (old default, very faint) | 90 = bright-black | 3 = italic | 2;3 = dim+italic
#   38;5;245 dimmer | 38;5;248 default | 38;5;250 / 38;5;252 brighter (256-color terminals)
: "${EC_TIP_SGR:=38;5;248}"

# Logging (privacy: off by default, §7)
: "${EC_LOG:=0}"
: "${EC_LOG_ORIGINAL:=0}"

# Backend (§4.2). One of: claude-cli | anthropic | openai
: "${EC_BACKEND:=claude-cli}"
: "${EC_CLAUDE_MODEL:=claude-haiku-4-5}"
: "${EC_ANTHROPIC_MODEL:=claude-haiku-4-5}"   # verify this resolves on the API; else use dated id
: "${EC_ANTHROPIC_BASE_URL:=https://api.anthropic.com}"   # host only; provider appends /v1/messages
: "${EC_OPENAI_MODEL:=gpt-4o-mini}"
: "${EC_OPENAI_BASE_URL:=https://api.openai.com/v1}"       # includes /v1; provider appends /chat/completions
: "${EC_OPENAI_MAX_TOKENS:=512}"   # generous: reasoning models (Groq gpt-oss/qwen3) spend tokens on hidden reasoning
# EC_OPENAI_REASONING_EFFORT: unset by default. Set ONLY for reasoning models on an
#   OpenAI-compatible endpoint to bound/disable thinking: Groq gpt-oss => low|medium|high; qwen3 => none.
# EC_ANTHROPIC_API_KEY / EC_OPENAI_API_KEY: unset by default
# EC_INNER_STATUSLINE: set by install.sh (original statusLine.command)

# Local grammar pre-pass (§3/§5 of the spec). One of: auto | harper | off
#   auto   = use Harper if $EC_HARPER_BIN is on PATH, else fall back to combined LLM (today)
#   harper = force Harper (if missing: log + fall back), off = never use Harper
: "${EC_GRAMMAR:=auto}"
: "${EC_HARPER_BIN:=harper-cli}"   # brew installs the one-shot CLI as `harper-cli` (NOT `harper`)
: "${EC_HARPER_DIALECT:=us}"       # American English — matches the coach's "sound like an American" goal
: "${EC_HARPER_GATE:=errors}"      # errors | any — which lint kinds gate the LLM

# Derived runtime dirs
EC_STATE_DIR="$EC_HOME/state"
EC_TIPS_DIR="$EC_HOME/tips"
EC_TMP_DIR="$EC_HOME/tmp"
EC_LOG_FILE="$EC_HOME/log.jsonl"

umask 077

[ -f "${EC_HOME}/config.local.sh" ] && . "${EC_HOME}/config.local.sh" || true
