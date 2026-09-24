---
name: sortd-release
description: Stage 5 of the Sortd pipeline. Gets a build ready for TestFlight or the App Store with release-manager: version and build bump, scripts/preflight.sh, docs/AppStoreChecklist.md walked item by item, release notes. Only Raj uploads. Use when Raj says "ship it", "release", "testflight", "app store build", "cut a build", "preflight", "ready to upload".
---

# Sortd stage 5: release

The router and agents get the build ready. **Only Raj archives and uploads.** No agent
touches App Store Connect, signing or Transporter.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. TestFlight or App Store.
2. The version (e.g. 1.0) and whether this is a new build of the same version.
3. Which commit: `main` at HEAD unless he names one. It must have CI green:
   `gh run list --branch main --limit 1`.

## Steps

1. `scripts/worktree-new.sh release-<version>-<build>` from `main`. A clean tree only.
2. Scripts first, in that worktree:
   - TestFlight: `scripts/preflight.sh`
   - App Store: `scripts/preflight.sh --appstore`
   - then `scripts/build.sh` and `scripts/test.sh`.
   Save the output. A preflight FAIL is a blocker, not a note.
3. Check the open decisions in `HANDOVER.md` that block a store build: `SORTD_BETA`
   still in Release, Sentry still linked, Google `gmail.readonly` not yet verified
   (`docs/GoogleVerification.md`), the privacy policy's named owner. For TestFlight,
   `SORTD_BETA` stays **on**.
4. Spawn `release-manager` (`subagent_type: release-manager`). Brief:
   - "Work only in `<path>`."
   - "Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
     `Spend.xcodeproj/project.pbxproj` for every target (app and widget) to
     `<version>` / `<build>`. Nothing else in the pbxproj."
   - "Walk `docs/AppStoreChecklist.md` top to bottom. Tick only what you checked in the
     repo, and say how. Mark each other item `needs Raj` or `not verified`. For
     App Store, the 'Before any App Store build' section must be all done."
   - "Write release notes in `docs/ReleaseNotes-<version>-<build>.md`: what changed
     since the last release notes file (the repo has no tags yet), in plain words,
     and the What's New text for the listing (under 4,000 characters)."
   - "Run `scripts/preflight.sh` (add `--appstore` for a store build) at the end and paste it."
   - "Do not upload. Do not touch signing, App Store Connect or the live site. Commit by name."
5. Rerun preflight yourself. Diff the pbxproj: only version fields changed.
6. Push and PR the bump the `sortd-build` way (steps 8 to 10). Merge only on CI green
   and Raj's word.
7. Hand Raj the upload list: the commit to archive, the version and build, the
   checklist items marked `needs Raj`, and the release notes path.

## Output

A merged version bump, `docs/ReleaseNotes-<version>-<build>.md`, and
`docs/AppStoreChecklist.md` with ticks backed by evidence.

## Gate (**hard**)

Raj archives in Xcode and uploads. Only Raj uploads. The pipeline stops here until
he says the build is up.

## Do not

- Do not upload, submit for review, or click anything in App Store Connect.
- Do not remove `SORTD_BETA` for a TestFlight build. Do remove it (via `sortd-build`) before an App Store one.
- Do not tick a checklist box nobody checked.
- Do not reuse a build number. Every upload needs a new one.
- Do not release from a folder with other sessions' uncommitted edits.
