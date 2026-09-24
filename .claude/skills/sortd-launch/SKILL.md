---
name: sortd-launch
description: Stage 6 of the Sortd pipeline. The growth agent writes launch copy (App Store listing, launch posts, beta emails, site copy) in the brand voice, checked against what the app really does. Raj publishes. Use when Raj says "launch", "write the listing", "launch post", "beta email", "app store copy", "announce it", "go live copy".
---

# Sortd stage 6: launch

Words only. `growth` drafts, the router checks every claim against the code and the
privacy label, and Raj publishes by hand.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. Which pieces: App Store listing, launch posts (which platforms), beta or launch
   email, site copy (which page).
2. What is launching: TestFlight beta or App Store, and the version.
3. Any offer or date to mention (Offer Code, launch day). Never guess a price or date.

## Steps

1. Scripts first. Check the facts the copy will lean on:
   - `scripts/preflight.sh --appstore` for a store launch (Sentry and `SORTD_BETA`
     decide what the privacy wording may say).
   - `cd <worktree>/docs && python3 check_listing.py` checks listing field lengths.
2. `scripts/worktree-new.sh launch-<topic>`. Keep the path.
3. Spawn `growth` (`subagent_type: growth`). Brief:
   - "Work only in `<path>`. Write only in `docs/marketing/`, `docs/AppStoreListing.md`,
     `docs/BetaEmails.md` and `site/` copy."
   - "Read `docs/marketing/brand-voice.md` first and follow it: roast the habit, never
     the person; short sentences; no words from its banned list; no exclamation marks."
   - "Only claim what the app does today. Free vs Pro is in CLAUDE.md ('Paid features').
     Privacy lines must match the App Privacy label and `site/privacy.html`."
   - "For each piece give two variants: one plain, one with more of the joke."
   - "Save launch posts to `docs/marketing/launch/<platform>.md`. Do not commit."
4. Router checks every factual line (features, price, 'no server', 'data stays on your
   phone', supported banks and currencies) against the code or docs, and marks each
   one checked or cut. Rerun `check_listing.py` if the listing changed.
5. Show Raj the files and the list of claims checked.

## Output

Draft copy in `docs/AppStoreListing.md`, `docs/marketing/launch/`, `docs/BetaEmails.md`,
or `site/` in the `launch-<topic>` worktree. PR it through `sortd-build` steps 8 to 10
when Raj is happy.

## Gate (**hard**)

Raj publishes: pastes the listing into App Store Connect, posts, sends the email,
deploys the site. No agent posts, sends or deploys.

## Do not

- Do not run `npx wrangler deploy`. Site deploys happen from one place, by Raj, from a
  clean tree that matches the pushed branch.
- Do not post, email, or touch App Store Connect.
- Do not invent reviews, user counts, press quotes or testimonials.
- Do not promise features that are only in a spec (CloudKit backup is not built).
- Do not name competitors in a way that could be read as a claim about them.
