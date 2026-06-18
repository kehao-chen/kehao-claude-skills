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

# Extract the payload between the first/last quote (curly U+201C/U+201D or ASCII ").
ec__sug_quoted() {
  printf '%s' "$1" | perl -CSDA -ne 'print $1 if /[\x{201c}"]([^\x{201c}\x{201d}"]*)[\x{201d}"]/'
}

# Deterministic concrete reason. Prefer Harper message; question-form/overlong/empty
# -> concrete phrase per kind. NEVER a bare bucket like "spelling"/"grammar".
ec__reason() {
  local m="$1" kind="$2"
  m="$(printf '%s' "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$m" in ''|*\?) m="" ;; esac
  if [ -n "$m" ]; then
    [ "$(printf '%s' "$m" | wc -m | tr -d ' ')" -gt 48 ] && m="$(printf '%s' "$m" | cut -c1-48)"
    printf '%s' "$m"; return 0
  fi
  case "$kind" in
    Spelling)       printf 'possible misspelling' ;;
    Typo)           printf 'likely typo' ;;
    Agreement)      printf 'subject–verb agreement' ;;
    Capitalization) printf 'capitalization' ;;
    Punctuation)    printf 'missing/incorrect punctuation' ;;
    Repetition)     printf 'repeated word' ;;
    Usage)          printf 'nonstandard usage' ;;
    Malapropism)    printf 'wrong word' ;;
    BoundaryError)  printf 'word-boundary error' ;;
    Eggcorn)        printf 'misheard phrase' ;;
    Nonstandard)    printf 'nonstandard form' ;;
    Grammar)        printf 'grammar mistake' ;;
    *)              printf '%s' "$(printf '%s' "$kind" | tr 'A-Z' 'a-z')" ;;
  esac
}

# Defense-in-depth for locally-built lines: strip control chars, cap length.
ec_sanitize_local() {
  local line; line="$(cat)"
  line="$(printf '%s' "$line" | LC_ALL=C tr -d '\000-\037\177')"
  local max n; max="${EC_MAX_TIP_LEN:-120}"
  n="$(printf '%s' "$line" | wc -m | tr -d ' ')"
  [ "$n" -gt "$max" ] && line="$(printf '%s' "$line" | cut -c1-"$max")…"
  printf '%s' "$line"
}

# $1=textfile $2=lint(JSON). echo "😇 a → b (reason)" + return 0, or return 1 (unrenderable).
ec_map_lint() {
  local tf="$1" lint="$2" cs ce kind msg matched sug action payload original improved frag
  cs="$(printf '%s' "$lint" | jq -r '.span.char_start // empty')"
  ce="$(printf '%s' "$lint" | jq -r '.span.char_end // empty')"
  kind="$(printf '%s' "$lint" | jq -r '.kind // empty')"
  msg="$(printf '%s' "$lint" | jq -r '.message // empty')"
  matched="$(printf '%s' "$lint" | jq -r '.matched_text // empty')"
  sug="$(printf '%s' "$lint" | jq -r '.suggestions[0] // empty')"
  [ -n "$cs" ] && [ -n "$ce" ] || return 1

  case "$sug" in
    'Replace with: '*) action="replace"; payload="$(ec__sug_quoted "$sug")" ;;
    'Insert '*)        action="insert";  payload="$(ec__sug_quoted "$sug")" ;;
    'Remove'*)         action="remove";  payload="" ;;
    *) return 1 ;;
  esac

  if [ "$action" = "replace" ]; then
    [ -n "$matched" ] && [ -n "$payload" ] || return 1
    original="$matched"; improved="$payload"
  else
    [ "$action" = "insert" ] && [ -z "$payload" ] && return 1
    frag="$(ec__render_edit "$tf" "$cs" "$ce" "$action" "$payload")" || return 1
    original="${frag%%$'\t'*}"; improved="${frag#*$'\t'}"
  fi
  [ -n "$original$improved" ] || return 1
  [ "$original" = "$improved" ] && return 1

  printf '😇 %s → %s (%s)' "$original" "$improved" "$(ec__reason "$msg" "$kind")" | ec_sanitize_local
}
