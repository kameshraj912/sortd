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

# Each task costs about 11.5 GB once it has built and run (4.5 GB build folder
# + 7 GB simulator). Twenty left behind filled the disk to 2.4 GB free
# (2 Oct 2026). So: no new task while the disk is low or too many are open.
free_gb=$(df -g / | awk 'NR==2 {print $4}')
open_sims=$(xcrun simctl list devices available 2>/dev/null | grep -c 'Sortd-' || true)
min_free="${SORTD_MIN_FREE_GB:-40}"; max_open="${SORTD_MAX_TASKS:-4}"
if [ "${free_gb:-0}" -lt "$min_free" ]; then
  die "only ${free_gb} GB free (need $min_free). Run scripts/clean.sh --yes and scripts/worktree-done.sh on finished tasks first."
fi
if [ "${open_sims:-0}" -ge "$max_open" ]; then
  die "$open_sims task simulators already exist (limit $max_open). Finish one first: scripts/worktree-audit.sh, then scripts/worktree-done.sh <task>."
fi

git -C "$main_root" fetch -q origin "$base" 2>/dev/null || true
git -C "$main_root" worktree add "$dest" -b "$task" "$base" >/dev/null || die "git worktree add failed"
"$main_root/scripts/install-hooks.sh" "$dest" >/dev/null
SORTD_SIM="Sortd-$task" "$dest/scripts/sim.sh" ensure >/dev/null

ok "worktree $dest on branch $task from $base, simulator Sortd-$task"
printf '%s\n' "$dest"
