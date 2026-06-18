#!/usr/bin/env bash
# Restore the user's original statusline (drift-aware) and remove the deployed
# wrapper. Leaves config.local.sh / secrets.env / tips / state intact.
# To also stop the hook, disable the plugin.
set -euo pipefail
EC_HOME="${EC_HOME:-$HOME/.claude/english-coach}"
SETTINGS="${EC_SETTINGS:-$HOME/.claude/settings.json}"
SL_CMD="$EC_HOME/statusline.sh"

command -v jq >/dev/null || { echo "unwire-statusline: jq is required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { echo "no settings.json — nothing to do"; exit 0; }

CUR="$(jq -r '.statusLine.command // ""' "$SETTINGS")"
# Only restore if the current statusline is still ours (exact path match); otherwise
# the user changed it since setup — respect that (drift-aware).
if [ "$CUR" != "$SL_CMD" ]; then
  echo "WARNING: statusLine.command is not english-coach ('$CUR') — leaving as-is (drift detected)."; exit 0
fi

# Recover the inner statusline from config.local.sh.
INNER=""
if [ -f "$EC_HOME/config.local.sh" ]; then
  INNER="$( . "$EC_HOME/config.local.sh" >/dev/null 2>&1; printf '%s' "${EC_INNER_STATUSLINE:-}" )"
fi

tmp="$SETTINGS.ectmp.$$"; trap 'rm -f "$tmp"' EXIT
if [ -n "$INNER" ]; then
  jq --arg sl "$INNER" '.statusLine.command = $sl' "$SETTINGS" > "$tmp"
else
  jq 'del(.statusLine)' "$SETTINGS" > "$tmp"
fi
jq empty "$tmp"; mv -f "$tmp" "$SETTINGS"; chmod 600 "$SETTINGS"
rm -f "$EC_HOME/statusline.sh"
echo "statusline restored${INNER:+ -> $INNER}. Open a NEW session to apply. (Disable the plugin to also stop the hook.)"
