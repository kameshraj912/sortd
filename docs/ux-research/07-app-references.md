# App references — what to borrow, 25 Sep 2026

Raj pointed at two sources: heyclicky.com and Pascio's post "6 clean and useful
iPhone apps" (Endel, Focus Flight, Flighty, One Sec, Pestle, TeuxDeux). Read on
25 Sep 2026. The apps themselves were not installed; this is what their own
marketing shows. Each line: what they do → what Sortd takes from it.

## Patterns worth taking

| Source | What they do | For Sortd | Sub-spec |
|---|---|---|---|
| heyclicky | A mascot with moods (ASCII faces, `^ ω ^`, `(¬_¬)`) and a playful, conversational voice; Lenny Rachitsky called its onboarding "my new favorite" | A light personality in onboarding, empty states and the activation moment: the receipt icon with a few expressions, one line of plain talk per screen, no corporate copy | onboarding, icons and assets |
| heyclicky | Free tier, student discount, referral page, public trust page and changelog | Since the app is free: a public changelog and a trust page on sortd.page ("what leaves your phone, what does not"), a referral link in Settings once analytics can count it | analytics, growth |
| Flighty | Live Activities and Dynamic Island for live status; "knows about your delay before the airline tells you" | A Live Activity while Gmail syncs ("checking 214 emails…") and for the monthly budget on the lock screen; proactive nudges: "on track to pass your budget by the 22nd" | optimistic UI, later a Live Activity sub-spec |
| Flighty | Award badges and press quotes on the first screenshot; dark, premium three-phone hero | App Store screenshot set: three-phone hero, one line per screen, badges when we have them | icons and assets, launch |
| Focus Flight | One visual metaphor for progress (the plane flies as you stay focused; leave and it crashes) | One visual for the month: the budget bar becomes a small journey or streak of "no-spend days"; loss framing is optional, keep it honest | onboarding (activation), Home |
| One Sec | Shows the measured effect back to the user ("half the time you close it instead") | Show outcomes, not just totals: "you spent 12% less than last month", "3 subscriptions you never used" | Insights, analytics events |
| Endel | Reads context (heart rate, weather, time of day) and adapts | Context for the add sheet: time of day and last shop suggest the merchant and category before typing | optimistic UI |
| Pestle | Capture from anywhere via the share sheet (IG reel → recipe) and sync to Calendar | A Share Extension: share a receipt screenshot, PDF or email from any app into Sortd; bills and subscriptions to Calendar | later sub-spec: share extension |
| TeuxDeux | "Nothing on it except your to-dos"; day-based paper list, swipe between days | Home stays minimal; Activity as a day-based list with horizontal day swipe; no dashboard clutter | Home, transitions |

## Patterns to leave alone

- Endel's biometrics and Focus Flight's app blocking need permissions and Screen Time APIs that do not fit a spending tracker.
- One Sec's interrupt-before-open pattern would be a "pause before you buy" feature; interesting, out of scope now.
- heyclicky's pricing tiers: irrelevant, the app is free.

## Not verified

App Store award claims on the slides (Apple Design Award, App of the Day) are the apps' own marketing. Nothing here was checked against the App Store.
