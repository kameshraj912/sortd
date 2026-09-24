#!/bin/bash
# What is in every worktree: dirty files, commits main lacks, merged or not.
#
#   scripts/worktree-audit.sh
#
# Read-only. Use it before deleting anything.
source "$(dirname "$0")/common.sh"
main_root="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"; main_root="${main_root%/.git}"

printf '%-22s %6s %6s %7s %7s %s\n' branch dirty ahead unique merged remote
git -C "$main_root" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  b="$(git -C "$wt" branch --show-current 2>/dev/null)"; [ -z "$b" ] && continue
  dirty="$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')"
  ahead="$(git -C "$main_root" rev-list --count main.."$b" 2>/dev/null)"
  unique="$(git -C "$main_root" log --oneline main.."$b" --cherry-pick --right-only --no-merges 2>/dev/null | wc -l | tr -d ' ')"
  merged="$(git -C "$main_root" branch --merged main | grep -c " $b$")"
  remote="$(git -C "$main_root" ls-remote --heads origin "$b" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%-22s %6s %6s %7s %7s %s\n' "$b" "$dirty" "$ahead" "$unique" "$merged" "$remote"
done
say ""
say "dirty = uncommitted files. unique = commits whose content is not on main (cherry-pick check)."
say "A worktree is safe to remove only when dirty=0 and unique=0."
