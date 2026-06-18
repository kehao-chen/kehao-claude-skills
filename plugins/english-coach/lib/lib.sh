# Shared pure-ish helpers. Sourced after config.sh.

# Normalize a session_id into a filesystem-safe key (<=64 chars).
ec_sid_key() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64
}

# Extract a top-level string field from JSON on stdin. jq -> python3 -> grep.
ec_json_get() {
  local key="$1" data
  data="$(cat)"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$data" | jq -r --arg k "$key" '.[$k] // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$data" | python3 -c '
import sys, json
k = sys.argv[1]
try:
    v = json.load(sys.stdin).get(k, "")
    sys.stdout.write(v if isinstance(v, str) else "")
except Exception:
    pass' "$key"
  else
    printf '%s' "$data" \
      | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
  fi
}

# Bump per-session seq atomically; echo the new value.
ec_seq_bump() {
  local f="$EC_STATE_DIR/$1.seq" n
  mkdir -p "$EC_STATE_DIR"
  n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" > "$f.tmp" && mv -f "$f.tmp" "$f"
  printf '%s' "$n"
}

ec_seq_current() {
  cat "$EC_STATE_DIR/$1.seq" 2>/dev/null || echo 0
}

# Atomic write: stdin -> $1 via temp + mv.
ec_atomic_write() {
  local d="$1"
  mkdir -p "$(dirname "$d")"
  cat > "$d.tmp.$$" && mv -f "$d.tmp.$$" "$d"
}
