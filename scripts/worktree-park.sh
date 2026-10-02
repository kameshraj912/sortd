#!/bin/bash
# Park a task whose branch still waits on a PR: free its simulator and build
# folder but keep the worktree, the branch and any uncommitted edits.
#
#   scripts/worktree-park.sh <task>     frees ~4 GB build + ~7 GB simulator
#
# Use it at the end of every session when `worktree-done.sh` is not yet
# allowed (branch unmerged). test.sh and build.sh recreate both on demand.
source "$(dirname "$0")/common.sh"

task="${1:-}"
[ -n "$task" ] || die "usage: worktree-park.sh <task>"
main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"
wt="$main_root/.claude/worktrees/$task"
[ -d "$wt" ] || die "no worktree at $wt"

if [ -d "$wt/.build" ]; then
  size="$(du -sh "$wt/.build" 2>/dev/null | cut -f1)"
  rm -rf "$wt/.build" && ok "removed $wt/.build ($size)"
fi

SORTD_SIM="Sortd-$task" "$main_root/scripts/sim.sh" delete
for suffix in se max; do
  SORTD_SIM="Sortd-$task-$suffix" "$main_root/scripts/sim.sh" delete 2>/dev/null | grep -v '^note' || true
done

dirty="$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')"
[ "$dirty" != 0 ] && warn "$task still has $dirty uncommitted files; they are kept"
ok "parked $task: worktree and branch kept, simulator and build folder gone"
