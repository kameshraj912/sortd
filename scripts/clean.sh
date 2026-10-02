#!/bin/bash
# Free disk: build folders of this checkout and every worktree, stale
# simulators with no matching worktree.
#
#   scripts/clean.sh          report what would go
#   scripts/clean.sh --yes    delete it
#
# Each build folder is ~4.5 GB and each task simulator ~7 GB; the disk hit
# 2.4 GB free on 2 Oct 2026 with twenty tasks left behind.
source "$(dirname "$0")/common.sh"
main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"
yes="${1:-}"

say "Build folders:"
git -C "$main_root" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  # `.build` is today's build folder; `build` is the old name, still in a few
  # old worktrees (7 GB in one). Only ever a folder git ignores.
  for d in "$wt/.build" "$wt/build"; do
    [ -d "$d" ] || continue
    git -C "$wt" check-ignore -q "$d" || continue
    say "  $(du -sh "$d" 2>/dev/null | cut -f1)  $d"
    [ "$yes" = "--yes" ] && rm -rf "$d"
  done
done

say "Simulators with no worktree:"
xcrun simctl list devices available | grep -oE 'Sortd-[a-z0-9-]+' | sort -u | while read -r sim; do
  task="${sim#Sortd-}"
  [ -d "$main_root/.claude/worktrees/$task" ] && continue
  say "  $sim"
  [ "$yes" = "--yes" ] && SORTD_SIM="$sim" "$main_root/scripts/sim.sh" delete
done

df -h / | tail -1 | awk '{print "Disk: " $4 " free of " $2}'
[ "$yes" = "--yes" ] || say "(dry run; pass --yes to delete)"
