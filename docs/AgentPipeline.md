# Sortd agent pipeline

How work gets done on Sortd: one chat routes to expert agents and fixed scripts.
Written 24 September 2026. This is the design of record; change it when the
pipeline changes.

## The idea

Raj talks to **one Claude Code chat**. That chat is the **router**. It never does
expert work itself. It reads the request, picks the lifecycle stage, and runs that
stage's recipe. A recipe mixes four kinds of parts:

| Part | Where | Deterministic? | What it is |
|---|---|---|---|
| Scripts | `scripts/*.sh` | yes | Build, test, simulators, worktrees, preflight, disk. Same input, same result. Exit 0 or fail. |
| Hooks | `scripts/hooks/` | yes | Hard gates on commit and push. No agent can talk its way past them. |
| Agents | `.claude/agents/*.md` | no | One job each, own model, fixed tools. Reviewers cannot write. Builders cannot merge. |
| Skills | `.claude/skills/sortd-*/SKILL.md` | recipe | One per stage: which scripts run first, which agents get called, what the exit gate is. |
| Workflows | `.claude/workflows/*.js` | recipe | Big fan-outs (bug hunt). Triggered by name so cost stays under Raj's control. |

Everything lives in this repo, so every Claude session in this folder gets the same graph.

## Router rules

The router (the main chat) follows these, in order:

1. **Classify** the request into one stage below. Say which. If it spans stages, do
   the earliest one first and stop at its gate.
2. **Scripts before agents.** If a script answers the question (does it build? do
   tests pass? what is in the worktrees?), run the script. Never ask an agent to
   guess what a script can measure.
3. **One worktree per task**, made with `scripts/worktree-new.sh`. Never give two
   agents the same worktree or simulator.
4. **Verify before acting on any agent report.** An agent surveying the wrong
   checkout once reported a P0 that did not exist. Check the branch and the file
   before spending time on a finding.
5. **Every finding goes through `finding-verifier`** before it is called a bug.
6. **Gates are Raj's.** A stage ends with something Raj sees: a doc, a table, a
   green PR. The router does not start the next stage on its own unless Raj has
   said "run everything"; then it still stops at the gates marked **hard**.
7. **Model choice.** Router: Fable. Judgement-heavy review and adversarial work:
   Opus. Repetitive, well-specified work: Sonnet. Model is one line per agent file.

## Agents

All under `.claude/agents/`. Frontmatter fields: `name`, `description` (when the
router should pick it), `tools`, `disallowedTools`, `model`, `effort`.

| Agent | Job | Writes | Model | Tools |
|---|---|---|---|---|
| `swift-builder` | Implements one approved change in its own worktree. Runs `scripts/build.sh` and `scripts/test.sh` before reporting. Never merges. | app code, tests | Fable (`inherit`) | Read, Edit, Write, Bash, Glob, Grep |
| `test-writer` | Writes Swift Testing cases first, from a behaviour list, TDD style. In-memory `ModelContainer`. Tags known bugs with `.knownBug`. | `SpendTests/` only | Sonnet | Read, Write, Edit, Bash, Glob, Grep |
| `code-reviewer` | Reviews a diff for correctness, Swift 6 concurrency, SwiftData rules in CLAUDE.md, and the "every source goes through `TransactionLogger`" rule. | nothing | Opus | Read, Grep, Glob, Bash |
| `abuse-tester` | Adversarial inputs: money and currency strings, dates, statement rows, backups, Gmail bodies, Shortcut text, intents. Writes failing tests tagged `.knownBug` and a findings table. | `SpendTests/` only | Opus | Read, Write, Bash, Glob, Grep |
| `ui-driver` | Drives the simulator: screenshots every screen at SE, Pro, Pro Max sizes; Dynamic Type AX5; VoiceOver labels via the accessibility tree; Reduce Motion; dark mode. Reports clipping, missing labels, dead controls. | screenshots to `.build/ui/` | Sonnet | Read, Bash, Glob, Grep, iOS Simulator tool |
| `finding-verifier` | Reproduces one claimed bug in the real code (a test or a script run). Verdict: CONFIRMED, NOT A BUG (with why), or CANNOT REPRODUCE. | nothing | Sonnet | Read, Bash, Glob, Grep |
| `release-manager` | Version and build bump, `scripts/preflight.sh`, TestFlight and App Store checklists in `docs/`, release notes. Never uploads; only Raj uploads. | `docs/`, pbxproj version fields | Sonnet | Read, Edit, Bash, Glob, Grep |
| `growth` | App Store listing, launch posts, beta emails, growth plan, ad scripts, in the voice of `docs/marketing/brand-voice.md`. Plain words. | `docs/marketing/`, `docs/AppStoreListing.md`, `site/` copy | Opus | Read, Write, Edit, Glob, Grep, WebSearch, WebFetch |
| `support` | Turns a user report (email, TestFlight feedback, review) into a reproducible finding for `finding-verifier`, and drafts the reply for Raj to send. | `docs/support/` | Sonnet | Read, Write, Glob, Grep, Bash |
| `architect` | One-page design docs in `docs/specs/` for new features, CloudKit backup, migrations, performance. Options with trade-offs and a recommendation. | `docs/specs/` | Opus | Read, Write, Glob, Grep, WebSearch, WebFetch |

Rules every agent file repeats:

- Work only inside the worktree path given in the brief. Never `cd` to the main folder.
- Use `scripts/*.sh`, never raw `xcodebuild` or `simctl`.
- Stage files by name. Never `git add -A`. Commit only when the brief says to.
- Report facts with evidence (command and output). Say "not verified" when it is not.
- Do not touch `SORTD_BETA`, signing, App Store Connect, or the live site.

## Lifecycle stages and their skills

Each is a skill at `.claude/skills/sortd-<stage>/SKILL.md`. Each skill states:
trigger phrases, inputs, the steps in order (scripts first), which agents run and
in what order or in parallel, the output artefact, and the gate.

| Stage | Skill | Runs | Output | Gate |
|---|---|---|---|---|
| 1 idea | `sortd-idea` | `architect` | `docs/specs/<date>-<topic>.md` | Raj approves the doc (**hard**) |
| 2 design | `sortd-design` | `architect`, then `test-writer` for the behaviour list | spec + test list | test list agreed |
| 3 build | `sortd-build` | `worktree-new.sh`, `test-writer`, `swift-builder`, `build.sh`, `test.sh`, `code-reviewer` | green branch + PR | build green, new tests pass, review clean |
| 4 test | `sortd-test` | `test.sh --all`; then workflow `bug-hunt` (`abuse-tester`, `ui-driver`, `code-reviewer` in parallel; `finding-verifier` on each finding) | findings table in `docs/BugHunt-<date>.md` | Raj triages the table |
| 5 release | `sortd-release` | `release-manager`: bump, `preflight.sh` (`--appstore` for store), checklists | release notes, checklist ticked | Raj uploads (**hard**) |
| 6 launch | `sortd-launch` | `growth`: listing, posts, emails | copy in `docs/` | Raj publishes (**hard**) |
| 7 grow | `sortd-grow` | `growth` works `docs/marketing/growth-plan.md` week by week | weekly report | weekly report read |
| 8 support | `sortd-support` | `support` then `finding-verifier`; confirmed bugs feed stage 4 | findings + draft replies | Raj sends replies (**hard**) |
| 9 scale | `sortd-scale` | `architect` (CloudKit, migrations, performance), then stages 3 and 4 | design doc | Raj approves the doc (**hard**) |

Cross-cutting skill: `sortd-status` prints where everything is: `worktree-audit.sh`,
open PRs, CI state, the known-bug count from `test.sh --known-bugs`, and the open
decisions list from `HANDOVER.md`.

## Big changes and overhauls

A change that touches several screens, a model, or how data flows is an **overhaul**.
Overhauls do not go through `sortd-build` as one task. They go through `sortd-idea`
first, and the architect's job there is to **cut it into sub-specs** that each fit one
build task, in an order where every step leaves the app working:

1. **One spec per sub-project**, `docs/specs/<date>-<overhaul>-<n>-<part>.md`, each with
   its own behaviour list and gate. The first doc is the overview: what changes, what does
   not, the order, and what a user sees after each step.
2. **Data first, screens second.** A SwiftData model change needs a migration plan
   (`VersionedSchema`, `SchemaMigrationPlan`) and a test that opens a store made by the
   previous version. That sub-spec goes first and ships alone.
3. **Feature flags for anything that replaces a screen.** The old screen stays until the
   new one passes the UI pass; the flag is a `#if DEBUG` env switch until then.
4. **Baseline before, UI pass after.** `ui-driver` screenshots the affected screens on
   `main` before the first sub-project starts, so "did it get worse" has an answer.
5. **Known-bug count may not rise.** `scripts/test.sh --known-bugs` before and after.
6. **Old branches are sources, not merges.** Port by hand from a named commit.

The router refuses to start a build task for an overhaul without an approved overview spec.

## The feel check (a gate, not a step)

Raj, 25 Sep 2026: how the app feels in the hand is what matters most. Code review reads code and
unit tests read logic; neither sees spacing, alignment, jank or a gesture that fights you. So every
change that touches a screen passes a **feel check** before it merges:

1. **Hands on, not stills.** Drive the screen on this worktree's simulator with the iOS Simulator
   control tool: tap every control, scroll to the end and back, pull to refresh, pull down to
   reveal search, swipe between days, open and dismiss every sheet. Default size, AX5, dark.
2. **Look for feel, not only bugs.** Spacing against the 16 pt system margin and standard section
   gaps; things touching or crowding (title to chips, icon to text); alignment; text too long for
   the screen; a control smaller than 44 pt; motion that jumps, lags or goes the wrong way; a
   sheet that flashes; anything that makes you stop and think.
3. **Compare with the last shots** of the same screen, and with the system apps and the
   references in `docs/ux-research/07-app-references.md` (WhatsApp for search, Flighty for polish).
4. **The router owns it.** If an agent cannot drive the simulator, the router does the feel check
   itself before merging. A change that has only stills does not merge.
5. **Raj's phone is the final word.** Haptics and real-speed animation only exist on a device:
   after each merge batch, `scripts/device.sh` puts the build on Raj's iPhone, and his notes come
   back through `sortd-support` as findings.

The checklist for step 2 lives in `docs/testing/ios-polish-checklist.md`.

## Testing in depth

- **Unit**: `scripts/test.sh` on an iOS 27 simulator. StoreKit tests are
  simulator-dependent; CI skips them, `--storekit` runs them locally.
- **Known bugs**: a failing test that documents a real bug is tagged
  `.tags(.knownBug)` and `.enabled(if: KnownBugs.run)`. `KnownBugs.run` is true
  when `SORTD_KNOWN_BUGS=1` reaches the test process; `scripts/test.sh
  --known-bugs` sets it. CI never sets it, so CI stays green and the bug list stays
  in the repo. Fixing a bug means removing its tag; the test then runs everywhere.
- **Adversarial**: `abuse-tester` works from a written attack list per area
  (`docs/testing/attacks.md`). New findings become known-bug tests.
- **Simulator**: `ui-driver` on the worktree's own simulator.
- **Bug hunt**: workflow `.claude/workflows/bug-hunt.js`: reviewers fan out per
  area, verifier confirms each finding, output is one table.

## Git rules

Kept from `~/.claude/rules/git-habits.md`: worktree per task, stage by name, commit
and push only when asked, never force `main`.

Added here:

- `scripts/worktree-new.sh` and `scripts/worktree-done.sh` do the setup and teardown,
  so the rules are code.
- `scripts/hooks/pre-commit` blocks secrets, large files, debug flags outside
  `#if DEBUG`, and Swift that does not parse.
- `scripts/hooks/pre-push` refuses direct pushes to `main`. Merges go through a PR
  with CI green. (GitHub branch protection needs a paid plan on a private repo; the
  hook is the local stand-in.)
- CI pins its Xcode version. Code must compile on that Xcode, not only on the newest.
- Base branch is `main`. `beta-prep` is retired.

## Open decisions (from HANDOVER.md, still open)

1. Sentry: remove it, or change the App Privacy label.
2. Privacy policy: names a person or a business entity. Needs a lawyer.
3. PR #8 (rename the `Spend/` folder to `Sortd/`): superseded except the rename itself.

## Lessons from the first overhaul

The free-app overhaul (PRs #30–#41, 25 Sep 2026) was the first big change to go through
this pipeline end to end. What to carry forward:

- **Gate by known-bug names, not counts.** A count alone can go up and down by
  coincidence while hiding a real regression; comparing the actual test names against
  the baseline list catches a swap that a count would miss.
- **Rebase before the gate, and stop on conflict.** Running `scripts/check.sh` on a
  branch that is behind `main` proves nothing about what will actually merge; a
  conflict found at gate time, not at merge time, is cheap to fix.
- **One agent per worktree, always.** Test files land in the shared `SpendTests/`;
  two agents in the same worktree corrupt each other's work.
- **Review is not optional.** `code-reviewer` found a P0 in three of the nine
  sub-specs. Skipping review to save time would have shipped those.
- **Builders must be allowed to stop and say so.** Test-writers sometimes pin a
  wrong premise into the test list; a builder who silently makes the code fit a
  wrong test is worse than one who stops and flags it.
- **Docs-only PRs skip CI.** A PR that touches only `docs/` needs no build or test
  run; gating it the same way as a code PR wastes the minutes that code PRs need.
