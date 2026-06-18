# english-coach: local grammar pre-pass via Harper (offline). Sourced after config.sh.
#
# Harper CLI (pinned expectation: harper-cli v2.x, 2026-06):
#  - `harper-cli lint --format json` prints a JSON array to stdout, THEN exits
#    non-zero when any lint is found (`bail!("Lints were found")`). So exit code
#    is NOT a success signal — judge success by parseable JSON on stdout.
#  - lint fields: {rule,kind,span{char_start,char_end} (CHAR idx, half-open),
#    message,priority,suggestions[] (Display strings, curly-quoted),matched_text}.
#  - CLI is experimental; parse defensively — any surprise => unavailable.

# kinds that GATE the LLM (everything else is style/idiom -> goes to the LLM).
EC_HARD_KINDS="Spelling Typo Grammar Agreement Capitalization Punctuation Usage Malapropism BoundaryError Eggcorn Nonstandard"

# echoes "harper" or "off"
ec_grammar_resolve() {
  case "${EC_GRAMMAR:-auto}" in
    off) printf 'off' ;;
    harper)
      if command -v "$EC_HARPER_BIN" >/dev/null 2>&1; then printf 'harper'
      else
        [ "${EC_LOG:-0}" = "1" ] && printf '{"grammar":"harper-missing"}\n' >> "$EC_LOG_FILE" 2>/dev/null
        printf 'off'
      fi ;;
    *) # auto
      if command -v "$EC_HARPER_BIN" >/dev/null 2>&1; then printf 'harper'; else printf 'off'; fi ;;
  esac
}

# stdin: harper JSON. stdout: ordered hard-candidate lints as JSONL (compact).
# return 2 iff stdout is not the expected harper shape (array of {lints:...}).
ec_grammar_candidates() {
  local json
  json="$(cat)"
  printf '%s' "$json" | jq -e \
    '(type=="array") and (length>=1) and (.[0]|type=="object") and (.[0]|has("lints"))' \
    >/dev/null 2>&1 || return 2
  printf '%s' "$json" | jq -c --arg hard "$EC_HARD_KINDS" --arg gate "${EC_HARPER_GATE:-errors}" '
    [.[].lints[]?]
    | (if $gate=="any" then .
       else ($hard|split(" ")) as $hk | map(select(.kind as $k | $hk|index($k)))
       end)
    | sort_by(.span.char_start, .priority) | .[]
  ' 2>/dev/null
}
