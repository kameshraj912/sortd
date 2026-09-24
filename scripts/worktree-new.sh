#!/bin/bash
# Start a task: its own worktree, branch and simulator, all named <task>.
#
#   scripts/worktree-new.sh <task> [base]      base defaults to main
#
# Worktrees live in .claude/worktrees/<task> so the Claude app sees them.
# Prints the path. Work only inside it.
source "$(dirname "$0")/common.sh"

task="${1:-}"; base="${2:-main}"
[ -n "$task" ] || die "usage: worktree-new.sh <task> [base]"
[[ "$task" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "task name: lowercase letters, digits, dashes"

main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"
dest="$main_root/.claude/worktrees/$task"
[ -e "$dest" ] && die "$dest already exists"

git -C "$main_root" fetch -q origin "$base" 2>/dev/null || true
git -C "$main_root" worktree add "$dest" -b "$task" "$base" >/dev/null || die "git worktree add failed"
"$main_root/scripts/install-hooks.sh" "$dest" >/dev/null
SORTD_SIM="Sortd-$task" "$dest/scripts/sim.sh" ensure >/dev/null

ok "worktree $dest on branch $task from $base, simulator Sortd-$task"
printf '%s\n' "$dest"
