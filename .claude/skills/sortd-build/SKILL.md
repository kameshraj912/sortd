---
name: sortd-build
description: Stage 3 of the Sortd pipeline. Builds one approved change TDD style in its own worktree (test-writer, then swift-builder, then code-reviewer), pushes the branch and opens a PR against main. Use when Raj says "build it", "make it", "fix this bug", "fix M3", "code it", "implement", "do the fix".
---

# Sortd stage 3: build

One task, one worktree, one branch, one simulator. Tests first, code second, review
third. Nothing merges without CI green and Raj saying so.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. What to build: a spec with an agreed `## Behaviour list`, or one confirmed bug id
   from a `docs/BugHunt-<date>.md` table (e.g. "M3"). Unconfirmed bugs go to
   `finding-verifier` first.
2. A task name: lowercase and dashes, e.g. `fix-currency-words`.
3. "OK to commit on `<task>`, push it and open a PR?" His yes covers this branch
   only. It never covers `main`.

## Steps

1. Scripts first, from the main folder: `git status` (read only; do not touch other
   sessions' changes) and `scripts/worktree-audit.sh` (is there already a branch for this?).
2. `scripts/worktree-new.sh <task>`. Keep the printed path. Every agent below gets it.
3. **Tests first.** Spawn `test-writer` (`subagent_type: test-writer`). Brief:
   - "Work only in `<path>`. Write only in `SpendTests/`."
   - The behaviour list or the bug's input, expected and actual.
   - "Swift Testing, in-memory `ModelContainer`. One suite `<Name>Tests`. Run
     `scripts/test.sh --only <Name>Tests` and show the tests fail for the right reason.
     If fixing a known bug, remove its `.knownBug` tag and `.enabled(if: KnownBugs.run)`."
   - "Commit your test files by name on `<task>`."
4. Router runs `scripts/test.sh --only <Name>Tests` itself. It must be red. If it is
   green, the tests do not test the change; send it back.
5. **Then code.** Only after test-writer is done, spawn `swift-builder`
   (`subagent_type: swift-builder`). Brief:
   - "Work only in `<path>`. Make `<Name>Tests` pass without editing them. If a test
     is wrong, stop and say why."
   - "Follow CLAUDE.md: every source through `TransactionLogger.log(_:in:)`, enums as
     raw strings, totals in `audValue`, debug flags inside `#if DEBUG`, compile on
     the CI Xcode (`#if compiler(>=...)` for new SDK symbols)."
   - "Run `scripts/build.sh` and `scripts/test.sh` before reporting. Paste the last
     lines. Commit by name on `<task>`. Do not push, do not merge."
6. Router checks the report with scripts, not trust: `scripts/check.sh` in the worktree
   (clean tree, build, full tests; its exit code is the answer, never grep a pipe). Add
   `--known-bugs` if a known bug was fixed, to see the count drop by one.
7. Spawn `code-reviewer` (`subagent_type: code-reviewer`). Brief: "Review
   `git -C <path> diff main...<task>`. Read only." Any **must fix** goes back to
   swift-builder, then steps 6 and 7 again. After two rounds still failing, stop and
   show Raj.
8. Router checks the commits: `git -C <path> status` is clean and
   `git -C <path> show --stat HEAD` lists only this task's files.
9. Push and PR:
   - `git -C <path> pull --rebase origin <task>` (skip if the branch is not on origin yet)
   - `git -C <path> push -u origin <task>`
   - `gh pr create --base main --head <task>` with a plain title and body: what, why,
     tests added, review result.
10. `gh pr checks <n> --watch`. Report the PR link and CI state to Raj.
11. Merge only when CI is green **and** Raj says merge:
    `gh pr merge <n> --merge --delete-branch`, then `scripts/worktree-done.sh <task>`.

## Output

A branch `<task>` with tests and code, a PR against `main`, and CI results.

## Gate

Build green, the new tests pass, review has no must-fix, PR open. Raj sees the PR link.
Merging is his call.

## Do not

- Do not let swift-builder start before the failing tests are committed.
- Do not run test-writer and swift-builder at the same time. One agent in a worktree at a time.
- Do not call raw `xcodebuild` or `simctl`. Use `scripts/`.
- Do not `git add -A`, `git add .`, `git commit -a`, or `--no-verify`. If a hook blocks, fix the cause.
- Do not push to `main`, force-push, or merge with CI red or pending.
- Do not touch `SORTD_BETA`, signing, or App Store Connect in a build task.
