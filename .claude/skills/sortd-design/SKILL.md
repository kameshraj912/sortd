---
name: sortd-design
description: Stage 2 of the Sortd pipeline. Turns an approved spec into a detailed design plus an agreed list of behaviours to test, using architect then test-writer. Use when Raj says "design it", "approved, next", "plan the build", "what tests", "test list", "break it down".
---

# Sortd stage 2: design

Input is a spec Raj approved in `sortd-idea` (or `sortd-scale`). Output is the same
spec with a design section and a behaviour list that `sortd-build` turns into tests.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. Path of the approved spec (`docs/specs/<date>-<topic>.md`). If there is no approved
   spec, stop and run `sortd-idea` first.
2. Which option he approved, if the doc has more than one.
3. Anything he wants in or out of the first build ("v1 without the widget").

## Steps

1. Scripts first. `scripts/worktree-audit.sh`: reuse the spec's worktree
   (`idea-<topic>`) if it is still there, or make `scripts/worktree-new.sh design-<topic>`
   and copy the spec in. One worktree, used by one agent at a time.
2. Spawn `architect` (Agent tool, `subagent_type: architect`). Brief:
   - "Work only in `<worktree path>`."
   - "Add a `## Design` section to `<spec path>`: screens and where they sit in the
     tabs, SwiftData model changes (and the migration step, see `SpendStore.swift`),
     how every new source goes through `TransactionLogger.log(_:in:)`, the Pro gate,
     VoiceOver labels on amounts and charts, and the order to build it in."
   - "Keep it under two pages. Do not write code. Do not commit."
3. Read the design. Check every named file and type exists (router rule 4).
4. Then, **after** the architect has finished, spawn `test-writer`
   (`subagent_type: test-writer`) in the same worktree. Brief:
   - "Read `<spec path>`. Return a behaviour list, one line each:
     `given <state>, when <action>, then <result>`, grouped by suite name. Include the
     edge cases from `docs/testing/attacks.md` that apply. Do not write test code yet.
     Do not write outside `SpendTests/`."
5. test-writer may not write in `docs/`, so the router pastes its list into the spec
   under `## Behaviour list`, word for word.
6. Show Raj the list: number of behaviours per suite and any that the spec did not ask
   for but the attack list suggests.

## Output

The spec at `docs/specs/<date>-<topic>.md`, now with `## Design` and
`## Behaviour list`. Uncommitted until Raj says.

## Gate

Raj agrees the behaviour list ("list is fine", or edits). Then `sortd-build` can start.
Soft gate: if Raj said "run everything", carry on to `sortd-build`.

## Do not

- Do not run architect and test-writer at the same time in one worktree.
- Do not let test-writer write Swift here. Tests come first in `sortd-build`.
- Do not add behaviours Raj did not ask for without marking them "suggested".
- Do not change the approved option. If the design shows it will not work, stop and tell Raj.
