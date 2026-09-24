---
name: sortd-idea
description: Stage 1 of the Sortd pipeline. Turns a new feature idea into a one-page design doc from the architect agent, for Raj to approve. Use when Raj says "new idea", "i want to add", "what if sortd could", "spec this", "write a spec", "idea:", "could we build".
---

# Sortd stage 1: idea

The router does not design. It gathers the idea, hands it to `architect`, checks the
doc against the code, and stops at Raj's approval. Design of record: `docs/AgentPipeline.md`.

## Inputs

Ask Raj for anything missing, **one question at a time**:

1. The idea in one sentence ("log cash spends by voice").
2. The problem it fixes, and for whom (Raj, beta testers, a user report).
3. Free or Pro. If unsure, say so in the brief; the architect proposes one.
4. Any hard limit: deadline, "no server", "must work offline", TestFlight first.

Do not ask about things the code can answer. Look them up.

## Steps

1. Scripts first. In the main folder run `git status` (read only) and
   `scripts/worktree-audit.sh` to see if a branch already covers this idea.
2. Search `docs/specs/` and `HANDOVER.md` ("Still to do", "Decisions still open") for
   an existing spec or a note on the topic. If one exists, give its path to the architect.
3. Make the task's worktree: `scripts/worktree-new.sh idea-<topic>`. Keep the printed path.
4. Spawn **one** `architect` agent (Agent tool, `subagent_type: architect`). Brief:
   - "Work only in `<worktree path>`. Do not cd anywhere else."
   - The idea, the problem, free or Pro, the limits, any prior spec path.
   - "Write `docs/specs/<YYYY-MM-DD>-<topic>.md`, one page: problem, 2 or 3 options
     with trade-offs, a recommendation, what it touches (models, `TransactionLogger`,
     Pro gate, App Privacy label, Google scope, migrations), open questions, and a
     rough size in days. Name the real files it changes."
   - "Sortd has no server and keeps data on the phone. Flag any option that breaks that."
   - "Do not write code. Do not commit."
5. Verify before showing Raj (router rule 4): open every file path the doc names and
   check it exists in the worktree. Fix or flag any that do not.
6. Show Raj the doc path and a five-line summary: the recommendation, the size, the
   open questions.

## Output

`docs/specs/<YYYY-MM-DD>-<topic>.md` in the `idea-<topic>` worktree, uncommitted.
Commit it on that branch only when Raj says so.

## Gate (**hard**)

Raj approves the doc, in words ("approved", "go with option B"). Until then nothing
moves to `sortd-design`. If he picks a different option, send that back to the same
architect brief and rerun step 4.

## Do not

- Do not write Swift, tests or site copy in this stage.
- Do not start stage 2 on your own, even if the doc looks obvious.
- Do not let the architect invent user numbers, prices or Apple rules. Anything not
  checked against a source says "not verified".
- Do not give the architect the main folder or another session's worktree.
- Do not treat an old spec as current without checking its date against `main`.
