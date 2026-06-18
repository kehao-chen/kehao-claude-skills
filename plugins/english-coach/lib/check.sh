#!/usr/bin/env bash
set -u
EC_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$EC_SELF_DIR/config.sh"
. "$EC_SELF_DIR/lib.sh"
. "$EC_SELF_DIR/skiprules.sh"

ec_check_main() {
  # Recursion guard (§4.1): a coach-spawned claude must not re-trigger us.
  [ -n "${ENGLISH_COACH_SKIP:-}" ] && exit 0

  local payload prompt sid sid_key seq tmpfile
  payload="$(cat)"
  prompt="$(printf '%s' "$payload" | ec_json_get prompt)"
  sid="$(printf '%s' "$payload" | ec_json_get session_id)"
  [ -z "$sid" ] && sid="default"
  sid_key="$(ec_sid_key "$sid")"

  # Bump seq on EVERY submit so stale tips auto-expire (§4.4).
  seq="$(ec_seq_bump "$sid_key")"

  # Redact URLs/paths BEFORE skip-check and dispatch: the link/path never reaches
  # the LLM, but the surrounding hand-typed prose still gets coached.
  prompt="$(printf '%s' "$prompt" | ec_redact)"

  # Skip => return now; bumped seq already invalidated any old tip.
  if ec_should_skip "$prompt"; then
    exit 0
  fi

  # Hand the prompt to the worker via a 600 temp file (never via argv, §7).
  mkdir -p "$EC_TMP_DIR"
  tmpfile="$EC_TMP_DIR/$sid_key.$seq.$$.txt"
  printf '%s' "$prompt" > "$tmpfile"
  chmod 600 "$tmpfile"   # explicit 600 (already enforced by umask 077)

  local worker="${EC_WORKER_CMD:-$EC_SELF_DIR/worker.sh}"
  if [ "${EC_DISPATCH_SYNC:-0}" = "1" ]; then
    # Suppress worker stdout: check.sh must NEVER write stdout (§7).
    "$worker" "$sid_key" "$seq" "$tmpfile" >/dev/null
  else
    nohup "$worker" "$sid_key" "$seq" "$tmpfile" < /dev/null >/dev/null 2>&1 &
  fi
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then ec_check_main "$@"; fi
