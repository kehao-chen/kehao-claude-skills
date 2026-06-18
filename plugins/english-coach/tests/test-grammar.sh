#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$HERE/../lib" && pwd)"
export EC_HOME="$(mktemp -d)"
. "$LIB/config.sh"
. "$LIB/lib.sh"
. "$LIB/grammar.sh"
. "$HERE/_assert.sh"

# --- ec_grammar_resolve ---
EC_GRAMMAR=off;    assert_eq "off -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=auto;   EC_HARPER_BIN="$HERE/fake-harper";   assert_eq "auto + present -> harper" "harper" "$(ec_grammar_resolve)"
EC_GRAMMAR=auto;   EC_HARPER_BIN="ec-no-such-bin-xyz";  assert_eq "auto + absent -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=harper; EC_HARPER_BIN="ec-no-such-bin-xyz";  assert_eq "harper + absent -> off" "off" "$(ec_grammar_resolve)"
EC_GRAMMAR=harper; EC_HARPER_BIN="$HERE/fake-harper";   assert_eq "harper + present -> harper" "harper" "$(ec_grammar_resolve)"

# --- ec_grammar_candidates ---
J_TWO='[{"file":"stdin","lint_count":2,"lints":[
  {"rule":"X","kind":"Style","span":{"char_start":1,"char_end":2},"message":"m","priority":5,"suggestions":["Replace with: “a”"],"matched_text":"a"},
  {"rule":"Y","kind":"Spelling","span":{"char_start":9,"char_end":16},"message":"sp?","priority":7,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}
]}]'
# gate=errors -> only the Spelling lint survives
assert_eq "candidates errors-only kind" "Spelling" \
  "$(printf '%s' "$J_TWO" | EC_HARPER_GATE=errors ec_grammar_candidates | jq -r .kind)"
# gate=any -> both, ordered by char_start (Style at 1 first)
assert_eq "candidates any first kind" "Style" \
  "$(printf '%s' "$J_TWO" | EC_HARPER_GATE=any ec_grammar_candidates | head -1 | jq -r .kind)"
# no hard lints -> empty, rc 0
J_STYLE='[{"file":"stdin","lint_count":1,"lints":[{"rule":"X","kind":"Style","span":{"char_start":1,"char_end":2},"message":"m","priority":5,"suggestions":[],"matched_text":"a"}]}]'
assert_eq "candidates none -> empty" "" "$(printf '%s' "$J_STYLE" | EC_HARPER_GATE=errors ec_grammar_candidates)"
printf '%s' "$J_STYLE" | EC_HARPER_GATE=errors ec_grammar_candidates >/dev/null; assert_rc "candidates parsed rc0" 0 $?
# bad shape -> rc 2
printf 'not json' | ec_grammar_candidates >/dev/null 2>&1; assert_rc "candidates bad -> rc2" 2 $?
printf '{"oops":1}' | ec_grammar_candidates >/dev/null 2>&1; assert_rc "candidates wrong-shape -> rc2" 2 $?

# --- ec__sug_quoted ---
assert_eq "quoted curly" "believe" "$(ec__sug_quoted 'Replace with: “believe”')"
assert_eq "quoted ascii" "a" "$(ec__sug_quoted 'Insert "a"')"
assert_eq "quoted none" "" "$(ec__sug_quoted 'Remove error')"
# --- ec__reason ---
assert_eq "reason declarative kept" "advice is uncountable" "$(ec__reason 'advice is uncountable' 'Usage')"
assert_eq "reason question -> phrase" "possible misspelling" "$(ec__reason 'Did you mean to spell “x” this way?' 'Spelling')"
assert_eq "reason empty -> phrase" "repeated word" "$(ec__reason '' 'Repetition')"

# --- ec_map_lint: Replace ---
TF="$(mktemp)"; printf 'I beleive it' > "$TF"
L_SP='{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"Did you mean to spell “beleive” this way?","priority":63,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}'
assert_eq "map replace spelling" "😇 beleive → believe (possible misspelling)" "$(ec_map_lint "$TF" "$L_SP")"
L_AGR='{"kind":"Agreement","span":{"char_start":0,"char_end":4},"message":"Use the singular verb here.","priority":10,"suggestions":["Replace with: “is”"],"matched_text":"are"}'
assert_eq "map replace agreement (message kept)" "😇 are → is (Use the singular verb here.)" "$(ec_map_lint "$TF" "$L_AGR")"
# no-op (matched == payload) -> unrenderable rc1
L_NOOP='{"kind":"Spelling","span":{"char_start":0,"char_end":1},"message":"x","priority":1,"suggestions":["Replace with: “are”"],"matched_text":"are"}'
ec_map_lint "$TF" "$L_NOOP" >/dev/null; assert_rc "map noop -> rc1" 1 $?
# unknown suggestion -> unrenderable rc1
L_UNK='{"kind":"Spelling","span":{"char_start":0,"char_end":1},"message":"x","priority":1,"suggestions":[],"matched_text":"are"}'
ec_map_lint "$TF" "$L_UNK" >/dev/null; assert_rc "map empty-sug -> rc1" 1 $?

# --- ec_map_lint: Insert / Remove (perl diff) ---
TF2="$(mktemp)"; printf 'I have cat' > "$TF2"
# Insert "a" before "cat": zero-width point at char 7 (after "have "), payload missing space
L_INS='{"kind":"Grammar","span":{"char_start":7,"char_end":7},"message":"Add the article.","priority":20,"suggestions":["Insert “a”"],"matched_text":""}'
assert_eq "map insert article" "😇 cat → a cat (Add the article.)" "$(ec_map_lint "$TF2" "$L_INS")"
TF3="$(mktemp)"; printf 'please return back to me' > "$TF3"
# Remove redundant "back": span covers " back" [13,18)
L_RM='{"kind":"Redundancy","span":{"char_start":13,"char_end":18},"message":"“back” is redundant","priority":30,"suggestions":["Remove error"],"matched_text":" back"}'
# Redundancy is style; for this unit test we call ec_map_lint directly (gate is tested elsewhere)
assert_eq "map remove redundant" "😇 return back → return (“back” is redundant)" "$(ec_map_lint "$TF3" "$L_RM")"
# perl absent OR unrenderable -> rc1 (simulate by an out-of-range span)
L_BAD='{"kind":"Grammar","span":{"char_start":99,"char_end":99},"message":"m","priority":1,"suggestions":["Insert “z”"],"matched_text":""}'
ec_map_lint "$TF2" "$L_BAD" >/dev/null; assert_rc "map oob span -> rc1" 1 $?

# --- ec_grammar_check: 4 states ---
export EC_HARPER_BIN="$HERE/fake-harper"
mk() { FAKE_HARPER_OUT="$(mktemp)"; printf '%s' "$1" > "$FAKE_HARPER_OUT"; export FAKE_HARPER_OUT; }
TFC="$(mktemp)"; printf 'I beleive it' > "$TFC"

# hard_tip — valid JSON WITH a hard error, harper exits 1 (lints found). Must still gate.
mk '[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":["Replace with: “believe”"],"matched_text":"beleive"}]}]'
export FAKE_HARPER_RC=1 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check hard_tip rc0 despite exit1" 0 "$rc"
assert_eq "check hard_tip line" "😇 beleive → believe (possible misspelling)" "$out"

# verified_clean — valid JSON, no hard lint, exit 0
mk '[{"file":"x","lint_count":0,"lints":[]}]'
export FAKE_HARPER_RC=0 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check verified_clean rc0" 0 "$rc"; assert_eq "check verified_clean empty" "" "$out"

# hard_unrenderable — valid JSON, hard error, but suggestions empty -> rc3, no line
mk '[{"file":"x","lint_count":1,"lints":[{"kind":"Spelling","span":{"char_start":2,"char_end":9},"message":"sp?","priority":1,"suggestions":[],"matched_text":"beleive"}]}]'
export FAKE_HARPER_RC=1 ; out="$(ec_grammar_check "$TFC")"; rc=$?
assert_rc "check hard_unrenderable rc3" 3 "$rc"; assert_eq "check hard_unrenderable empty" "" "$out"

# unavailable — garbage stdout (any exit)
mk 'not json at all'
export FAKE_HARPER_RC=0 ; ec_grammar_check "$TFC" >/dev/null 2>&1; assert_rc "check unavailable rc2" 2 $?

ec_tests_done
