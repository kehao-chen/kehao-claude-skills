#!/usr/bin/env bash
set -u
EC_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$EC_SELF_DIR/config.sh"
. "$EC_SELF_DIR/lib.sh"

ec_statusline_main() {
  local payload sid sid_key out cur tipfile header body sgr
  payload="$(cat)"

  # Tip styling: SGR params from config (digits/semicolons only — config is trusted,
  # but reject malformed values so a typo can't inject arbitrary escape sequences).
  sgr="${EC_TIP_SGR:-38;5;248}"
  case "$sgr" in ''|*[!0-9\;]*) sgr='38;5;248' ;; esac

  # Run the original statusline (verbatim, full shell semantics) with the same payload.
  if [ -n "${EC_INNER_STATUSLINE:-}" ]; then
    out="$(printf '%s' "$payload" | sh -c "$EC_INNER_STATUSLINE")"
  else
    out=""
  fi

  sid="$(printf '%s' "$payload" | ec_json_get session_id)"
  [ -z "$sid" ] && sid="default"
  sid_key="$(ec_sid_key "$sid")"
  cur="$(ec_seq_current "$sid_key")"
  tipfile="$EC_TIPS_DIR/$sid_key"

  if [ -f "$tipfile" ]; then
    header="$(head -1 "$tipfile")"
    body="$(sed -n '2,$p' "$tipfile" | LC_ALL=C tr -d '\000-\037\177')"   # defense-in-depth: strip control chars
    if [ "$(printf '%s' "$body" | wc -m | tr -d ' ')" -gt "${EC_MAX_TIP_LEN:-120}" ]; then
      body="$(printf '%s' "$body" | cut -c1-"${EC_MAX_TIP_LEN:-120}")…"   # defense-in-depth: re-truncate
    fi
    if [ "$header" = "seq=$cur" ] && [ -n "$body" ]; then
      # Reset any color the inner statusline left open BEFORE appending ours.
      # ccstatusline (and many statuslines) end on an open SGR with no trailing
      # reset; without this the open background bleeds into our tip line and the
      # newline-fill. Then our styled tip (EC_TIP_SGR), then a final reset.
      printf '%s\033[0m\n\033[%sm%s\033[0m' "$out" "$sgr" "$body"
      return 0
    fi
  fi
  # No tip: still terminate with a reset so the inner statusline's open color
  # cannot bleed past our output into Claude Code's footer.
  printf '%s\033[0m' "$out"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ec_statusline_main "$@"; fi
