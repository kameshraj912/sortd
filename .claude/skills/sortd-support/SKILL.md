---
name: sortd-support
description: Stage 8 of the Sortd pipeline. Turns a user report (email, TestFlight feedback, App Store review) into a reproducible finding, gets it checked by finding-verifier, and drafts a reply for Raj to send. Confirmed bugs feed stage 4. Use when Raj says "support", "a user said", "tester reported", "reply to this", "bad review", "feedback came in", "someone emailed".
---

# Sortd stage 8: support

The user gets a reply that is true. The bug gets a repro. Raj sends every reply himself.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. The report itself, pasted (email, TestFlight feedback text, review).
2. Where it came from (email, TestFlight, App Store review) and the app version and
   build if shown.
3. The user's device and iOS version, if known. If not, the draft reply asks for it.

## Steps

1. `scripts/worktree-new.sh support-<YYYYMMDD>-<slug>`. Keep the path.
2. Scripts first. Check whether it is known: search the latest `docs/BugHunt-*.md` and
   `docs/support/`. If a known-bug test looks like the same bug, run
   `scripts/test.sh --known-bugs --only <Suite>` in the worktree and read the result.
3. Spawn `support` (`subagent_type: support`). Brief:
   - "Work only in `<path>`. Write only in `docs/support/`."
   - "Here is the report: <text>. Write `docs/support/<YYYY-MM-DD>-<slug>.md` with:
     what the user saw, the smallest steps that should reproduce it, the input (the
     exact email body, Shortcut text or statement row if given), expected vs actual,
     and which area of `docs/testing/attacks.md` it belongs to."
   - "Draft two replies: one short and plain, one warmer. Simple words. No promises
     of dates. Do not say it is fixed until it is merged."
   - "Replace the user's name, email address and any card or account digits with
     placeholders. Do not commit."
4. After support is done, spawn `finding-verifier` (`subagent_type: finding-verifier`)
   in the same worktree. Brief: "Reproduce this finding in the real code:
   <repro from the doc>. Verdict CONFIRMED, NOT A BUG (why), or CANNOT REPRODUCE, with
   the command and output."
5. Router checks the verdict's file and branch (router rule 4) and adds the verdict to
   the support doc.
6. CONFIRMED: add the row to the next `docs/BugHunt-<date>.md` table and offer
   `sortd-build` for the fix. NOT A BUG: the reply explains how it works. CANNOT
   REPRODUCE: the reply asks the one question that would unblock it.
7. Show Raj the verdict and both reply drafts.

## Output

`docs/support/<YYYY-MM-DD>-<slug>.md` with the repro, the verdict and two reply drafts.

## Gate (**hard**)

Raj sends the reply, from his own account. No agent sends email, answers a review, or
replies in TestFlight.

## Do not

- Do not send anything, and do not create Gmail drafts unless Raj asks.
- Do not store the user's email address, full name or card digits in the repo.
- Do not promise a fix date or a refund. Refunds go through Apple, not us.
- Do not call it a bug before `finding-verifier` confirms it.
- Do not argue with a review. Thank, explain, ask one question.
