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

ec_tests_done
