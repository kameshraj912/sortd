#!/bin/bash
# The router's gate for a branch: clean tree, build, full test run.
# Exits non-zero on any failure and prints the failing test names, so a
# calling job can rely on the exit code instead of grepping a pipe (a pipe
# masked two red runs on 24 Sep 2026).
#
#   scripts/check.sh                 clean tree + build + tests
#   scripts/check.sh --allow-dirty   skip the clean-tree check
#   scripts/check.sh --all           also run known-bug and StoreKit tests
source "$(dirname "$0")/common.sh"

allow_dirty=0; extra=()
for a in "$@"; do
  case "$a" in
    --allow-dirty) allow_dirty=1 ;;
    --all|--known-bugs|--storekit) extra+=("$a") ;;
    *) die "unknown flag $a" ;;
  esac
done

say "check: $(branch_name) at $(git -C "$ROOT" rev-parse --short HEAD)"
if [ $allow_dirty -eq 0 ] && [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  git -C "$ROOT" status --short
  die "tree is not clean; commit or pass --allow-dirty"
fi

"$ROOT/scripts/build.sh" || exit 1
# ${extra[@]+...}: an empty array is "unbound" under set -u on macOS bash 3.2.
if ! "$ROOT/scripts/test.sh" ${extra[@]+"${extra[@]}"}; then
  say ""
  say "failing tests:"
  grep -E '✘ Test [A-Za-z0-9_]+\(\) (failed|recorded an issue)' "$ROOT/.build/test.log" \
    | sed 's/^[^✘]*✘ Test //; s/ recorded an issue.*//; s/ failed.*//' | sort -u
  exit 1
fi
ok "check passed"
