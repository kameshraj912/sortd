# Sortd roadmap and status

One list for everything. Updated 22 Sep 2026. Each item has an owner:
**Raj** (only you can do it), **Claude** (I run it), or **Both**.

## How the work is run

Claude acts as CEO / project manager: plans, splits work, merges, reports.
Every feature passes these gates before it reaches `beta-prep`:

| Role | What they check |
|---|---|
| Product design lead | Every screen matches Sortd's style (Theme.swift): fonts, spacing, cards, colour only for categories. Screenshots side by side. |
| Engineering lead (CTO) | Code review: correctness, privacy, no secrets, tests added, no debug flags outside `#if DEBUG`. |
| QA lead | Full test suite, Release build, preflight, simulator walk-through: light, dark, large text, smallest iPhone. |
| Brand and copy lead | Wording is short and plain; voice guide followed; no humour where it's banned. |
| Compliance | Apple review guidelines, Google data policy, privacy page and App Store label match what the app really does. |
| Finance (CFO) | Monthly costs below. Nothing paid is switched on without Raj. |

Raj approves: anything visual (from screenshots), anything that costs money, anything public.

## Phase 0: Beta release candidate (now)

| Item | Status | Owner |
|---|---|---|
| Apple Pay tap bug (taps silently dropped) | Done, in beta-rc1 | Claude |
| Beta: Pro free, no paywall, Redeem Code for later | Done, in beta-rc1 | Claude |
| Settings split into sub-pages, Sortd style | Done, in beta-rc1 | Claude |
| Settings text smaller + title-under-status-bar bug | In progress (QA) | Claude |
| Crash reports ready, preflight fixed, beta playbook, payments guide | Done, in beta-rc1 | Claude |
| Full QA pass on beta-rc1 | In progress | Claude |
| Launch screen: "sortd" wordmark + animated bars | In progress | Claude |
| Trim in-app text to need-to-know | In progress | Claude |
| Pull to refresh + confetti for real wins | In progress | Claude |
| Speed + clear loading states (Gmail connect etc.) | In progress | Claude |
| Final merge + final QA of everything above | Next | Claude |
| Sentry organisation (US) + project key | In progress | Raj signs up, Claude sets up |
| Apple Developer enrolment | Waiting | Raj |
| App Store Connect: app record, TestFlight test info | After enrolment | Both |
| Upload build to TestFlight, invite first 10 testers | After enrolment + final QA | Both |

## Phase 1: Beta weeks 1-2

| Item | Status | Owner |
|---|---|---|
| PostHog (free): privacy-safe usage counts + A/B flags | Waiting for sign-up | Raj signs up, Claude builds |
| Brand voice guide (subtle roasting, "cheeky mode") | Draft being written | Claude drafts, Raj approves |
| Voice pass: add approved lines to the app | After approval | Claude |
| Weekly beta routine: read feedback, fix, new build | Starts with first build | Both |
| Font sizes app-wide (after Settings fix is approved) | Next | Claude |

## Phase 2: Beta weeks 3-4

| Item | Status | Owner |
|---|---|---|
| Forwarding inbox: deploy and test with real Gmail/Outlook | Built, not deployed | Claude; Raj turns on Workers Paid + Email Routing |
| Privacy page + App Store label for the inbox | After deploy | Claude |
| Google answer on CASA; decide Gmail sign-in vs forwarding | Waiting for Google; decide by mid-Nov | Raj decides |

## Phase 3: Before App Store launch

| Item | Status | Owner |
|---|---|---|
| Multi-step paywall (3 steps + locked-feature sheet), in-app design | Being designed | Claude builds, Raj approves |
| Trial lengths (yearly 14-21 days, monthly 7 days?) | To decide | Raj |
| A/B test: one-page vs three-step paywall (PostHog) | After paywall | Claude |
| Offer codes in App Store Connect | Later | Raj |
| Remove SORTD_BETA (`preflight.sh --appstore`) | At launch | Claude |
| iCloud backup (CloudKit), known gap | To plan | Claude |
| Refunds that never come back (known gap) | To plan | Claude |
| Trademark opinion ("Get Sortd" is a registered AU mark) | Not started | Raj |
| Singapore PDPA: name a data protection officer, publish contact | Not started | Raj |
| Small Business Program (15% instead of 30%) | After enrolment | Raj |

## Monthly costs (CFO)

| Item | Cost | Status |
|---|---|---|
| Apple Developer | US$99 / year | Enrolment pending |
| sortd.page domain | ~US$12-20 / year | Paying |
| Sentry (crash reports) | Free plan | Setting up |
| PostHog (usage + A/B) | Free up to 1M events / month | Not set up |
| Cloudflare Workers Paid (inbox, own tracking later) | US$5 / month flat; covers thousands of users | Not on yet |
| CASA security check (only if Google insists and we keep Gmail sign-in) | US$675-855 / year | Not decided |
