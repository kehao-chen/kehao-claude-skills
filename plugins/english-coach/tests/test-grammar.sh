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

ec_tests_done
