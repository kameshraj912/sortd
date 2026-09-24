#!/bin/bash
# Finish a task: remove its worktree, simulator and build folder.
#
#   scripts/worktree-done.sh <task>            refuses if the branch is unmerged or dirty
#   scripts/worktree-done.sh <task> --force    remove anyway (work is lost)
#
# The branch is deleted only when main already contains it.
source "$(dirname "$0")/common.sh"

task="${1:-}"; force="${2:-}"
[ -n "$task" ] || die "usage: worktree-done.sh <task> [--force]"
main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"
wt="$main_root/.claude/worktrees/$task"

if [ -d "$wt" ]; then
  dirty="$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')"
  if [ "$dirty" != 0 ] && [ "$force" != "--force" ]; then
    git -C "$wt" status --short
    die "$task has $dirty uncommitted files. Commit them or pass --force."
  fi
  git -C "$main_root" worktree remove ${force:+--force} "$wt" || die "worktree remove failed"
  ok "removed worktree $wt"
fi

if git -C "$main_root" show-ref --quiet "refs/heads/$task"; then
  if git -C "$main_root" branch -d "$task" 2>/dev/null; then
    ok "deleted branch $task (merged)"
  elif [ "$force" = "--force" ]; then
    git -C "$main_root" branch -D "$task" && ok "force-deleted branch $task"
  else
    warn "branch $task kept: not merged into main"
  fi
fi

SORTD_SIM="Sortd-$task" "$main_root/scripts/sim.sh" delete
