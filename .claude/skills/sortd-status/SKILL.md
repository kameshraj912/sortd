---
name: sortd-status
description: Cross-cutting status view for Sortd. Prints every worktree, open PRs, CI state, the known-bug count and the open decisions, from scripts and gh, not memory. Use when Raj says "where are we", "status", "whats open", "sortd status", "catch me up on sortd", "what's left", "prs?".
---

# Sortd status

Read only. Every line comes from a command or a file, not from memory.

## Inputs

None needed. If Raj names one branch or PR, show just that.

## Steps

Run these and keep the output. Steps 1 to 4 can run at once; step 5 is slow.

1. `scripts/worktree-audit.sh` (from the main folder; it is read only). Note any
   worktree with dirty > 0 or unique > 0, and any with dirty = 0, unique = 0 and
   merged = 1 (safe to remove with `scripts/worktree-done.sh <task>`, but only if Raj says).
2. `gh pr list` for open PRs: number, title, branch, draft or not.
3. `gh run list --limit 5` for the last CI runs: branch, result, age.
4. Read `HANDOVER.md` "Decisions still open" and the "Open decisions" list in
   `docs/AgentPipeline.md`. List each once, in plain words.
5. Known-bug count. In a clean worktree at `main`
   (`scripts/worktree-new.sh status-<YYYYMMDD>`), run `scripts/test.sh --known-bugs`
   and report the number of failing tests and their suite names. Say it takes a few
   minutes. Remove it after: `scripts/worktree-done.sh status-<YYYYMMDD>`.
   If Raj wants it fast, skip this step and say the count was not measured.
6. Also note the newest `docs/BugHunt-*.md` and its date, and how many rows are still
   untriaged.
7. Disk: `scripts/clean.sh` (dry run) lists every build folder and orphan simulator and
   ends with the free space. Under 50 GB free, say so first and suggest
   `scripts/clean.sh --yes` plus `scripts/worktree-park.sh` for parked branches.

## Output

Printed in the chat, nothing saved:

```
Worktrees   <n> total, <n> with uncommitted work, <n> safe to remove
PRs         #<n> <title> (<branch>) ... or "none open"
CI          last 5: <pass>/<fail>, latest on main: <result>
Known bugs  <n> failing (<suites>)   or "not measured"
Bug hunt    docs/BugHunt-<date>.md, <n> untriaged
Decisions   1. ... 2. ... 3. ...
Next        the one thing that unblocks the most
```

Under 20 lines.

## Gate

None. Raj reads it. Do not start any stage from here unless he asks.

## Do not

- Do not remove, stash or commit anything. Status is read only.
- Do not run tests in the main folder or in another session's worktree.
- Do not report a count you did not measure. Say "not measured".
- Do not guess CI state from memory; `gh run list` or nothing.
