---
name: sortd-test
description: Stage 4 of the Sortd pipeline. Runs the full test suite, then the bug-hunt workflow (reviewers per area, every finding checked by finding-verifier) and the ui-driver simulator pass, and writes one findings table to docs/BugHunt-<date>.md. Use when Raj says "test it", "bug hunt", "find bugs", "break it", "hunt", "abuse test", "is it solid".
---

# Sortd stage 4: test

Scripts first, then the fan-out. Nothing is called a bug until `finding-verifier`
says CONFIRMED and the router has checked the file and line on the right branch.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. What to test: `main` at HEAD (default) or a named branch.
2. "The bug hunt runs about 10 agents. Start it?" The workflow is triggered by name so
   the cost stays his call. A yes covers one run.
3. Include the UI pass (`ui-driver`, needs its own simulator)? Default yes.

## Steps

1. Make a clean copy: `scripts/worktree-new.sh hunt-<YYYYMMDD> <branch>`. Keep the path.
   Never hunt in the main folder or a worktree with someone's uncommitted edits.
2. In that worktree run `scripts/test.sh --all` (known bugs + StoreKit). Write down the
   pass, fail and skip counts and every failing name.
   - A failure **not** tagged `.knownBug` is a real regression. Stop, show Raj, and
     send it to `sortd-build` before hunting.
   - Known-bug failures are expected. Record the count.
3. Start the workflow: Workflow tool with `name: "bug-hunt"` and
   `args: {worktree: "<hunt path>"}`. It fans out five reviewers (money-parsing,
   gmail-security, data-backup, ui-intents-widget, statement-import) that work from
   `docs/testing/attacks.md`, then runs `finding-verifier` on the top five findings by
   severity. It returns `{confirmed, rejected, unverified}` and writes nothing itself.
4. While it runs, in parallel, make a second worktree `scripts/worktree-new.sh ui-<YYYYMMDD> <branch>`
   and spawn `ui-driver` (`subagent_type: ui-driver`) there. Brief: "Work only in
   `<ui path>`, on simulator `Sortd-ui-<YYYYMMDD>`. Screenshot every screen at SE, Pro and
   Pro Max; Dynamic Type AX5; VoiceOver labels from the accessibility tree; Reduce
   Motion; dark mode. Save to `.build/ui/`. Report clipping, missing labels and dead
   controls as {title, screen, device, steps, expected, actual, screenshot}."
   Then spawn one `finding-verifier` per ui-driver finding, one at a time.
5. Verify the verifiers (router rule 4): for each CONFIRMED finding, open the file and
   line in the hunt worktree and check the branch with `git -C <path> branch --show-current`.
6. Check what the reviewers wrote: `git -C <hunt path> status`. New tests must be in
   `SpendTests/` only and tagged `.tags(.knownBug)` with `.enabled(if: KnownBugs.run)`.
   Run `scripts/test.sh` (CI mode) there. It must still pass.
7. Write `docs/BugHunt-<YYYY-MM-DD>.md` in the hunt worktree, in the shape of
   `docs/BugHunt-2026-09-22.md`:
   - Title `# Bug hunt — <D Mon YYYY>`, then one paragraph: tools and agents run, the
     `test.sh --all` counts, what "proved" and "traced" mean.
   - Tables `## Fix before TestFlight`, `## Fix soon`: `| # | Bug | Where | Status |`.
     Ids by area: M money, G Gmail, D data/backup, U UI/intents/widget, S statement.
     Status is `proved` (a test or script reproduced it) or `traced` (read in code).
   - `## Low` as one dense line, like the old doc.
   - `## Rejected`: each NOT A BUG or CANNOT REPRODUCE, with the verifier's reason.
   - `## Not checked`: findings over the top-five cap that no verifier saw. Never drop them silently.
   - `## Status`: the date and "untriaged".
8. Show Raj the table and the counts. Commit the doc and the known-bug tests on
   `hunt-<YYYYMMDD>` only when he says so.
9. Free the disk before the session ends (CLAUDE.md "6. Finish"). Copy any screenshots
   Raj wants out of `.build/ui/`, then `scripts/worktree-done.sh ui-<YYYYMMDD>` and
   `scripts/worktree-park.sh hunt-<YYYYMMDD>` (done, not park, once the hunt branch is
   merged). Two worktrees with simulators are ~22 GB left behind otherwise.

## Output

`docs/BugHunt-<YYYY-MM-DD>.md`, known-bug tests in `SpendTests/`, screenshots in
`.build/ui/` of the ui worktree.

## Gate

Raj triages the table: which rows to fix now, later, or never. Fixes go through
`sortd-build`, one task per bug or per small group.

## Do not

- Do not fix bugs in this stage. Find, verify, write down.
- Do not run the workflow again without asking. Each run costs about ten agents.
- Do not give ui-driver the hunt worktree or its simulator.
- Do not list a finding as a bug if it only came from a reviewer.
- Do not trust an agent's file and line without opening it (the "P0 FlatTabBar" trap).
- Do not use the iOS 26.x simulator; StoreKit tests fail there for no code reason.
