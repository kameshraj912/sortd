#!/bin/bash
# Free disk: build folders of this checkout and every worktree, stale
# simulators with no matching worktree.
#
#   scripts/clean.sh          report what would go
#   scripts/clean.sh --yes    delete it
#
# Each DerivedData is ~3.5 GB; the disk once hit 98% and git started failing.
source "$(dirname "$0")/common.sh"
main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"
yes="${1:-}"

say "Build folders:"
git -C "$main_root" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  d="$wt/.build"
  [ -d "$d" ] || continue
  say "  $(du -sh "$d" 2>/dev/null | cut -f1)  $d"
  [ "$yes" = "--yes" ] && rm -rf "$d"
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
