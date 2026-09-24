---
name: sortd-scale
description: Stage 9 of the Sortd pipeline. Big structural work (CloudKit backup, SwiftData migrations, performance at large data sizes) gets a design doc from the architect first, then goes through build and test. Use when Raj says "scale", "cloudkit", "icloud backup", "backup", "migration", "schema change", "it's slow", "performance".
---

# Sortd stage 9: scale

Structural changes touch every user's data. Design first, approve, then build and
hunt. The biggest open gap is backup: SwiftData is local-only today (HANDOVER.md
"Still to do" 3).

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. Which job: CloudKit backup and sync, a schema migration, or performance.
2. For performance: which screen or action is slow, on which device, with about how
   many transactions. A number, not "slow".
3. Any limit: free or Pro, "must work with iCloud off", ship before or after App Store v1.

## Steps

1. Scripts first. Measure before designing:
   - `scripts/worktree-audit.sh` for an existing branch on this.
   - `scripts/worktree-new.sh scale-<topic>`. Keep the path.
   - `scripts/test.sh --only MigrationTests` and `--only BackupTests` in it, to know the
     current state.
   - For performance, there is no timing script yet. The architect's doc must say how
     to measure (for example a test that seeds N transactions and times the query), and
     that measurement is built first.
2. Spawn `architect` (`subagent_type: architect`). Brief:
   - "Work only in `<path>`. Write `docs/specs/<YYYY-MM-DD>-<topic>.md`, one page."
   - "Read `Spend/Services/SpendStore.swift`, `Backup.swift`, `Spend/Models/`, and
     `docs/BugHunt-2026-09-22.md` (D1, D2, D4, D5 are backup and migration bugs)."
   - CloudKit: "Say which model rules CloudKit sync needs and which of our models break
     them today (unique attributes, non-optional properties without defaults,
     relationships). Cover conflict rules, what happens to the existing JSON backup,
     iCloud signed out, and the App Privacy label."
   - Migration: "A `VersionedSchema` and `SchemaMigrationPlan` from the current models,
     and a test that opens an old store and migrates it."
   - "Options with trade-offs, a recommendation, and the rollback if it goes wrong on a
     user's phone. Sortd has no server; keep it that way. Do not write code."
3. Verify the doc's claims about our code (router rule 4): each named file, model and
   attribute exists on this branch. Apple API claims without a source are marked
   "not verified".
4. Show Raj the recommendation, the risk to existing data, and the size.
5. After approval: `sortd-design` for the behaviour list, `sortd-build` for the change,
   then `sortd-test` on the branch before merge. Entitlement or iCloud container changes
   need Raj in Xcode (signing is his).

## Output

`docs/specs/<YYYY-MM-DD>-<topic>.md` in the `scale-<topic>` worktree.

## Gate (**hard**)

Raj approves the doc. Nothing is built before that. After the build, a second gate:
`sortd-test` has run on the branch and Raj has triaged it.

## Do not

- Do not change the SwiftData schema without a migration plan and a test that migrates
  an old store. A bad migration can crash every launch for every user.
- Do not add a server, an account system or analytics to solve a scale problem.
- Do not edit signing, entitlements or the iCloud container in the pbxproj. Raj does that in Xcode.
- Do not tune performance by guess. Measure, change one thing, measure again.
