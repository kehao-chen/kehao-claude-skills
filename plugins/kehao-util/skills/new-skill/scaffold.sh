#!/usr/bin/env bash
# new-skill scaffolder.
#   Usage: scaffold.sh <name> <description> [plugin]
#
# Safety model (see design §5): the DESTINATION is the current working directory,
# which MUST be a marketplace repo root. Installed skills run from the plugin cache
# (~/.claude/plugins/cache/...), which is NOT the repo — so we hard-verify the cwd
# before writing anything, and never overwrite an existing skill. The TEMPLATE is
# read from this script's own directory so it resolves no matter the cwd.
set -uo pipefail

NAME="${1:-}"
DESC="${2:-}"
PLUGIN="${3:-kehao-util}"
[ -n "$PLUGIN" ] || PLUGIN="kehao-util"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPL="$SELF_DIR/templates/SKILL.md.tmpl"

die() { printf 'new-skill: %s\n' "$*" >&2; exit 1; }

# --- argument checks ---
[ -n "$NAME" ] || die 'missing <name>. Usage: new-skill <name> "<description>" [plugin]'
[ -n "$DESC" ] || die 'missing <description>. Usage: new-skill <name> "<description>" [plugin]'
case "$NAME" in
  *[!a-z0-9-]*) die "name must be kebab-case [a-z0-9-]: '$NAME'" ;;
  -*|*-)        die "name must not start or end with '-': '$NAME'" ;;
esac

# --- destination must be a marketplace repo root (cwd), not the plugin cache ---
[ -f ".claude-plugin/marketplace.json" ] \
  || die "current directory is not a marketplace root (no .claude-plugin/marketplace.json in $(pwd))"
[ -f "plugins/$PLUGIN/.claude-plugin/plugin.json" ] \
  || die "plugin '$PLUGIN' not found here (no plugins/$PLUGIN/.claude-plugin/plugin.json)"
[ -f "$TMPL" ] || die "template not found: $TMPL"

DEST="plugins/$PLUGIN/skills/$NAME"
[ -e "$DEST" ] && die "skill already exists: $DEST (refusing to overwrite)"

# --- write (safe substitution via env, so description may contain / & $ etc.) ---
mkdir -p "$DEST"
EC_NAME="$NAME" EC_DESC="$DESC" perl -pe '
  s/\{\{NAME\}\}/$ENV{EC_NAME}/g;
  s/\{\{DESCRIPTION\}\}/$ENV{EC_DESC}/g;
' "$TMPL" > "$DEST/SKILL.md" || die "failed to write $DEST/SKILL.md"

printf 'created %s\n' "$DEST/SKILL.md"
printf 'next: ./scripts/validate.sh  then  /reload-plugins (dev)  or  /plugin marketplace update\n'
