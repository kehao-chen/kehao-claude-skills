#!/usr/bin/env bash
# Run every tests/test-*.sh; non-zero exit if any file reports a failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$here"/test-*.sh; do
  [ -e "$t" ] || continue
  echo "== ${t##*/} =="
  bash "$t" || fail=1
done
exit "$fail"
