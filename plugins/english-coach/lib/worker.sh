#!/usr/bin/env bash
set -u
EC_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$EC_SELF_DIR/config.sh"
. "$EC_SELF_DIR/lib.sh"

# Sanitize raw model output (stdin) -> a single safe tip line, or empty. §4.2 H4.
ec_sanitize_tip() {
  local raw line
  raw="$(cat)"
  # remove all control chars (kills ANSI/ESC, newlines, tabs); keep printable + UTF-8
  line="$(printf '%s' "$raw" | LC_ALL=C tr -d '\000-\037\177')"
  # trim leading/trailing whitespace
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # explicit "no issue" tokens
  case "$line" in ""|OK|ok|none|None|NONE) printf ''; return 0 ;; esac
  # format whitelist (anchored): must start with "😇 ", contain "→", end with ")"
  case "$line" in
    '😇 '*'→'*'('*')') : ;;
    *) printf ''; return 0 ;;
  esac
  # no-op guard: drop tips whose fragment is identical on both sides of the arrow
  # (e.g. "appreciate → appreciate") — nothing to teach, just noise.
  local before after
  before="${line#😇 }"; before="${before%%→*}"
  after="${line#*→}"; after="${after%%(*}"
  before="$(printf '%s' "$before" | sed 's/^[[:space:]"'"'"']*//; s/[[:space:]"'"'"']*$//')"
  after="$(printf '%s' "$after" | sed 's/^[[:space:]"'"'"']*//; s/[[:space:]"'"'"']*$//')"
  [ -n "$before" ] && [ "$before" = "$after" ] && { printf ''; return 0; }
  # length cap (best-effort char count)
  local max n
  max="${EC_MAX_TIP_LEN:-120}"
  n="$(printf '%s' "$line" | wc -m | tr -d ' ')"
  if [ "$n" -gt "$max" ]; then
    line="$(printf '%s' "$line" | cut -c1-"$max")…"
  fi
  printf '%s' "$line"
}

# Load the rubric/system prompt once.
ec_rubric() { cat "$EC_SELF_DIR/prompt-template.txt"; }

# claude-cli: rubric in argv (non-sensitive), user prompt via stdin. Isolated only
# partially (non-bare loads global config); recursion guarded by ENGLISH_COACH_SKIP.
ec_provider_claude_cli() {
  local pf="$1"
  ( cd /tmp && ENGLISH_COACH_SKIP=1 claude -p --model "$EC_CLAUDE_MODEL" "$(ec_rubric)" < "$pf" )
}

# POST via a 600-perm curl config file so the API key NEVER appears in argv (ps-safe).
# $1=url  $2=reqfile  $3..=extra "Header: value" strings (incl. the auth header)
ec__curl_cfg_post() {
  local url="$1" reqf="$2"; shift 2
  local cfg out h
  cfg="$(mktemp "$EC_TMP_DIR/cfg.XXXXXX")"   # 600 via umask in config.sh
  {
    printf 'url = "%s"\n' "$url"
    for h in "$@"; do printf 'header = "%s"\n' "$h"; done
    printf 'header = "content-type: application/json"\n'
    printf 'data-binary = "@%s"\n' "$reqf"
    printf 'silent\nshow-error\nfail\n'
  } > "$cfg"
  out="$(curl --config "$cfg" 2>/dev/null)"
  rm -f "$cfg"
  printf '%s' "$out"
}

ec_provider_anthropic() {
  local pf="$1" url body reqf key out
  mkdir -p "$EC_TMP_DIR"
  key="${EC_ANTHROPIC_API_KEY:-${ANTHROPIC_API_KEY:-}}"
  url="${EC_ANTHROPIC_BASE_URL%/}/v1/messages"
  body="$(jq -n --arg m "$EC_ANTHROPIC_MODEL" --arg sys "$(ec_rubric)" --rawfile p "$pf" \
    '{model:$m, max_tokens:120, system:$sys, messages:[{role:"user", content:$p}]}')"
  reqf="$(mktemp "$EC_TMP_DIR/req.XXXXXX")"; printf '%s' "$body" > "$reqf"
  out="$(ec__curl_cfg_post "$url" "$reqf" "x-api-key: $key" "anthropic-version: 2023-06-01")"
  rm -f "$reqf"
  printf '%s' "$out" | jq -r '.content[0].text // empty'
}

ec_provider_openai() {
  local pf="$1" url body reqf out
  mkdir -p "$EC_TMP_DIR"
  url="${EC_OPENAI_BASE_URL%/}/chat/completions"
  # Reasoning models (Groq gpt-oss/qwen3) need token headroom and an optional
  # reasoning_effort knob; only emit reasoning_effort when explicitly configured.
  body="$(jq -n --arg m "$EC_OPENAI_MODEL" --arg sys "$(ec_rubric)" --rawfile p "$pf" \
    --argjson mt "${EC_OPENAI_MAX_TOKENS:-512}" --arg re "${EC_OPENAI_REASONING_EFFORT:-}" \
    '{model:$m, max_tokens:$mt, messages:[{role:"system",content:$sys},{role:"user",content:$p}]}
     + (if $re == "" then {} else {reasoning_effort:$re} end)')"
  reqf="$(mktemp "$EC_TMP_DIR/req.XXXXXX")"; printf '%s' "$body" > "$reqf"
  out="$(ec__curl_cfg_post "$url" "$reqf" "Authorization: Bearer ${EC_OPENAI_API_KEY:-}")"
  rm -f "$reqf"
  printf '%s' "$out" | jq -r '.choices[0].message.content // empty'
}

# Dispatch by EC_BACKEND. $1 = prompt file. Echoes RAW model text (caller sanitizes).
ec_run_provider() {
  case "$EC_BACKEND" in
    claude-cli) ec_provider_claude_cli "$1" ;;
    anthropic)  ec_provider_anthropic "$1" ;;
    openai)     ec_provider_openai "$1" ;;
    *) printf '' ;;
  esac
}

ec_worker_main() {
  local sid_key="$1" seq="$2" pf="$3" raw tip
  # Always clean up the prompt temp file, even on early return.
  # Use double-quotes so $pf is expanded NOW (while in scope as a local var),
  # not when the EXIT trap fires after this function returns to the script level.
  # shellcheck disable=SC2064
  trap "rm -f '$pf'" EXIT

  raw="$(ec_run_provider "$pf")"
  tip="$(printf '%s' "$raw" | ec_sanitize_tip)"

  # Seq guard (§4.4): only write if no newer prompt has arrived.
  [ "$(ec_seq_current "$sid_key")" = "$seq" ] || return 0

  mkdir -p "$EC_TIPS_DIR"
  printf 'seq=%s\n%s' "$seq" "$tip" | ec_atomic_write "$EC_TIPS_DIR/$sid_key"

  # Optional logging (off by default, §7).
  if [ "${EC_LOG:-0}" = "1" ]; then
    mkdir -p "$EC_HOME"
    if [ "${EC_LOG_ORIGINAL:-0}" = "1" ] && command -v jq >/dev/null 2>&1; then
      jq -nc --arg s "$seq" --arg b "$EC_BACKEND" --arg t "$tip" --rawfile o "$pf" \
        '{seq:$s, backend:$b, tip:$t, original:$o}' >> "$EC_LOG_FILE" 2>/dev/null || true
    else
      printf '{"seq":"%s","backend":"%s","has_tip":%s}\n' \
        "$seq" "$EC_BACKEND" "$([ -n "$tip" ] && echo true || echo false)" >> "$EC_LOG_FILE"
    fi
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ec_worker_main "$@"; fi
