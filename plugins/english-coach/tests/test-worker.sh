#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$HERE/../lib" && pwd)"
export EC_HOME="$(mktemp -d)"
. "$LIB/worker.sh"          # pulls in config.sh + lib.sh + grammar.sh; sets EC_SELF_DIR
. "$HERE/_assert.sh"

export EC_HARPER_BIN="$HERE/fake-harper"
MARK="$(mktemp)"
# stub the LLM provider: record the template it was called with, emit a canned tip
ec_run_provider() { printf '%s' "$2" > "$MARK"; printf '😇 utilize → use (just say "use")'; }

run_worker() { # $1=harper-json $2=harper-rc ; echoes the written tip body
  local sid="s1" seq=1
  : > "$MARK"
  FAKE_HARPER_OUT="$(mktemp)"; printf '%s' "$1" > "$FAKE_HARPER_OUT"; export FAKE_HARPER_OUT
  export FAKE_HARPER_RC="$2"
  mkdir -p "$EC_STATE_DIR"; printf '%s' "$seq" > "$EC_STATE_DIR/$sid.seq"
  local pf; pf="$(mktemp)"; printf 'I beleive utilize it' > "$pf"
  ( ec_worker_main "$sid" "$seq" "$pf" )
  sed -n '2,$p' "$EC_TIPS_DIR/$sid"
}

SP_RENDER='[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}]}]'
SP_EMPTY='[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":[],"matched_text":"beleive"}]}]'

# hard_tip: local line, provider NOT called (privacy gate)
TIP="$(run_worker "$SP_RENDER" 1)"
assert_eq "worker hard_tip line"        "😇 beleive → believe (possible misspelling)" "$TIP"
assert_eq "worker hard_tip no provider" "" "$(cat "$MARK")"

# verified_clean: idiom-only provider
TIP="$(run_worker '[{"file":"x","lint_count":0,"lints":[]}]' 0)"
assert_eq "worker verified_clean tmpl" "prompt-template-idiom.txt" "$(cat "$MARK")"
assert_eq "worker verified_clean tip"  '😇 utilize → use (just say "use")' "$TIP"

# hard_unrenderable: no provider, empty tip
TIP="$(run_worker "$SP_EMPTY" 1)"
assert_eq "worker hard_unrenderable no provider" "" "$(cat "$MARK")"
assert_eq "worker hard_unrenderable empty tip"   "" "$TIP"

# unavailable (garbage): combined provider
run_worker 'not json' 0 >/dev/null
assert_eq "worker unavailable tmpl" "prompt-template.txt" "$(cat "$MARK")"

# EC_GRAMMAR=off: never call harper -> combined provider even though a hard error exists
EC_GRAMMAR=off run_worker "$SP_RENDER" 1 >/dev/null
assert_eq "worker off -> combined" "prompt-template.txt" "$(cat "$MARK")"

ec_tests_done
