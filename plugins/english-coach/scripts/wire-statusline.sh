#!/usr/bin/env bash
# Wire english-coach's statusline display.
#
# Claude Code plugins cannot set the main statusLine, and ${CLAUDE_PLUGIN_ROOT}
# changes on every plugin update — so we deploy the wrapper to a STABLE path
# (~/.claude/english-coach) and point settings.json there, preserving the user's
# current statusline as the "inner" one. Idempotent; backs up settings first.
set -euo pipefail
umask 077

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBDIR="$(cd "$SELF/.." && pwd)/lib"
EC_HOME="${EC_HOME:-$HOME/.claude/english-coach}"
SETTINGS="${EC_SETTINGS:-$HOME/.claude/settings.json}"
SL_CMD="$EC_HOME/statusline.sh"

command -v jq >/dev/null || { echo "wire-statusline: jq is required" >&2; exit 1; }
mkdir -p "$EC_HOME/backups"; chmod 700 "$EC_HOME" "$EC_HOME/backups"

# 1. Deploy the wrapper + its deps to the stable path.
for f in statusline.sh config.sh lib.sh; do cp "$LIBDIR/$f" "$EC_HOME/$f"; done
chmod +x "$EC_HOME/statusline.sh"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
ORIG_SL="$(jq -r '.statusLine.command // ""' "$SETTINGS")"

# 2. Already wired? idempotent no-op. Compare to the actual target path (not a
#    hard-coded substring) so it's correct regardless of EC_HOME.
if [ "$ORIG_SL" = "$SL_CMD" ]; then
  echo "statusline already wired -> $SL_CMD (inner preserved)"; exit 0
fi

# 3. Save the current statusline as the inner one. Update only the
#    EC_INNER_STATUSLINE line; preserve other config.local.sh lines (backend, etc.).
CL="$EC_HOME/config.local.sh"
inner_line="EC_INNER_STATUSLINE=$(printf '%q' "$ORIG_SL")"
if [ -f "$CL" ]; then
  grep -v '^EC_INNER_STATUSLINE=' "$CL" > "$CL.tmp" 2>/dev/null || true
  { printf '%s\n' "$inner_line"; cat "$CL.tmp"; } > "$CL"; rm -f "$CL.tmp"
else
  printf '%s\n' "$inner_line" > "$CL"
fi
chmod 600 "$CL"

# 4. Backup + patch settings.json.
ts="$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$EC_HOME/backups/settings.$ts.json"; chmod 600 "$EC_HOME/backups/settings.$ts.json"
tmp="$SETTINGS.ectmp.$$"; trap 'rm -f "$tmp"' EXIT
jq --arg sl "$SL_CMD" '.statusLine = ((.statusLine // {"type":"command"}) + {"command": $sl})' "$SETTINGS" > "$tmp"
jq empty "$tmp"
mv -f "$tmp" "$SETTINGS"; chmod 600 "$SETTINGS"
echo "statusline wired -> $SL_CMD (inner saved to config.local.sh)."
echo "Open a NEW Claude Code session for it to take effect."
