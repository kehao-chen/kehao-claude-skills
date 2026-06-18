# Replace URLs and file paths with neutral placeholders so a hand-typed message
# that merely *contains* a link/path still gets its prose coached, while the URL/
# path itself NEVER leaves the machine (privacy). Placeholders use "(...)" — never
# "[" or "{" — so they don't trip the array/JSON-start skip rule below.
# If perl is unavailable, pass through unchanged; the URL/path rules in
# ec_should_skip then act as the fallback (skip the whole message).
ec_redact() {
  if command -v perl >/dev/null 2>&1; then
    perl -CSDA -pe '
      s{(?:https?|ftp)://\S+}{(url)}gi;            # http(s)/ftp URLs
      s{(?<![\w.])www\.[^\s]+}{(url)}gi;           # bare www.* URLs
      s{(?<!\S)[A-Za-z]:\\[^\s]+}{(path)}g;        # Windows paths  C:\...
      s{(?<!\S)~?\.{0,2}/[^\s]+}{(path)}g;         # /abs  ./rel  ../rel  ~/home paths
      s{(?<!\S)[^\s/]*/[^\s/]+/[^\s]+}{(path)}g;   # any token with >=2 slashes
    ' 2>/dev/null
  else
    cat
  fi
}

# Returns 0 = SKIP (do not check), 1 = CHECK. §6 of the spec.
ec_should_skip() {
  local p="$1"

  # multiline => pasted block / code / log
  if [ "${EC_SKIP_MULTILINE:-1}" -eq 1 ]; then
    case "$p" in *"
"*) return 0 ;; esac
  fi

  # leading slash (command) or ! (bash passthrough)
  case "$p" in
    /*|!*) return 0 ;;
  esac

  # URL
  case "$p" in
    *http://*|*https://*) return 0 ;;
  esac

  # path-like: 2+ slashes anywhere, ".." relative, "./", "~/", or any backslash (Windows/escape)
  case "$p" in
    */*/*|*../*|*./*|*~/*|*\\*) return 0 ;;
  esac

  # command-like: first word in denylist, or contains a " --" flag
  case "$p" in *" --"*) return 0 ;; esac
  local first
  first="$(printf '%s' "$p" | awk '{print $1}')"
  case "$first" in
    kubectl|az|git|docker|docker-compose|curl|wget|sudo|ssh|scp|psql|mysql|npm|npx|uv|pip|python|python3|node|bash|sh|brew|kubectx|helm|terraform|jq|grep|sed|awk|cat|ls|cd|rm|mv|cp|chmod|export) return 0 ;;
  esac

  # log-like: leading timestamp digit, common log levels, or JSON/array start
  case "$p" in
    [0-9]*|\{*|\[*) return 0 ;;
    ERROR*|WARN*|WARNING*|INFO*|DEBUG*|TRACE*|FATAL*|Traceback*|Exception*) return 0 ;;
  esac

  # symbol ratio: percent of non-alnum (LC_ALL=C, ASCII view) too high => code/config
  local total alnum sym_pct
  total="$(printf '%s' "$p" | LC_ALL=C tr -d '[:space:]' | wc -c | tr -d ' ')"
  if [ "$total" -gt 0 ]; then
    alnum="$(printf '%s' "$p" | LC_ALL=C tr -cd '[:alnum:]' | wc -c | tr -d ' ')"
    sym_pct=$(( (total - alnum) * 100 / total ))
    [ "$sym_pct" -gt "${EC_SYMBOL_RATIO_MAX:-30}" ] && return 0
  fi

  # count ASCII-letter "words" (run length) for English-volume heuristics
  local awords
  awords="$(printf '%s' "$p" | LC_ALL=C tr -cs 'A-Za-z' '\n' | grep -c '.')"

  # mostly non-English (e.g. Chinese): any non-ASCII present AND few English words
  if printf '%s' "$p" | LC_ALL=C grep -q '[^ -~]'; then
    [ "$awords" -lt "${EC_MIN_WORDS:-4}" ] && return 0
  fi

  # too short
  [ "$awords" -lt "${EC_MIN_WORDS:-4}" ] && return 0

  # too long (pasted)
  [ "$awords" -gt "${EC_MAX_WORDS:-40}" ] && return 0

  # too many sentences
  local sents
  sents="$(printf '%s' "$p" | tr -cd '.!?' | wc -c | tr -d ' ')"
  [ "$sents" -gt "${EC_MAX_SENTENCES:-3}" ] && return 0

  return 1   # do the check
}
