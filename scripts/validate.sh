#!/usr/bin/env bash
# Validate the kehao-claude-skills marketplace and its plugins.
# Core = the official `claude plugin validate --strict`; plus local consistency checks
# the runtime validator doesn't cover (marketplace<->dir listing, version agreement).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

MP=".claude-plugin/marketplace.json"
[ -f "$MP" ] || { printf 'FAIL: missing %s (run from the repo root)\n' "$MP" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 2; }

# 1 & 2. Official validator (marketplace, then each plugin) — if the CLI is present.
if command -v claude >/dev/null 2>&1; then
  printf '== claude plugin validate --strict . ==\n'
  claude plugin validate --strict . || err "marketplace manifest invalid"
  for p in plugins/*/; do
    [ -d "$p" ] || continue
    printf '== claude plugin validate --strict %s ==\n' "$p"
    claude plugin validate --strict "$p" || err "plugin invalid: $p"
  done
else
  printf 'WARN: "claude" CLI not found — skipping official validation, running consistency checks only\n' >&2
fi

# 3. Consistency checks.
printf '== consistency checks ==\n'

# (a) each marketplace plugin: source dir exists, has plugin.json, versions agree
while IFS=$'\t' read -r name source mver; do
  pj="${source#./}/.claude-plugin/plugin.json"
  if [ ! -f "$pj" ]; then err "plugin '$name': source '$source' has no $pj"; continue; fi
  pver="$(jq -r '.version // ""' "$pj")"
  if [ -n "$mver" ] && [ "$mver" != "$pver" ]; then
    err "version mismatch '$name': marketplace=$mver vs plugin.json=$pver (bump both together)"
  fi
done < <(jq -r '.plugins[] | [.name, .source, (.version // "")] | @tsv' "$MP")

# (b) each plugins/* dir is listed in the marketplace
for p in plugins/*/; do
  [ -d "$p" ] || continue
  src="./${p%/}"
  listed="$(jq -r --arg s "$src" '.plugins[] | select(.source==$s) | .name' "$MP")"
  [ -n "$listed" ] || err "plugins dir '$p' is not listed in $MP (source $src)"
done

# (c) each skill has a description in its frontmatter
shopt -s nullglob
for s in plugins/*/skills/*/SKILL.md; do
  awk 'NR==1&&$0!="---"{exit 1} /^description:[[:space:]]*[^[:space:]]/{found=1} /^---$/&&NR>1{exit found?0:1}' "$s" \
    || err "skill missing a non-empty description: $s"
done
shopt -u nullglob

if [ "$fail" -eq 0 ]; then
  nplug="$(jq '.plugins | length' "$MP")"
  nskill="$(ls -d plugins/*/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
  printf 'OK: %s plugin(s), %s skill(s)\n' "$nplug" "$nskill"
else
  printf 'validation FAILED\n' >&2
  exit 1
fi
