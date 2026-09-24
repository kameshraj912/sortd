---
name: sortd-grow
description: Stage 7 of the Sortd pipeline. The growth agent works docs/marketing/growth-plan.md week by week, from the numbers Raj gives it, and writes a weekly report with what to keep, drop and try next. Use when Raj says "grow", "weekly report", "how are posts doing", "growth plan", "next week's posts", "marketing week".
---

# Sortd stage 7: grow

One week at a time. The plan is `docs/marketing/growth-plan.md`. The agent can not see
TikTok, Instagram or App Store Connect, so numbers come from Raj.

## Inputs

Ask Raj, **one question at a time**, only for what is missing:

1. Which week (ISO week, e.g. 2026-W40). Default: this week.
2. The numbers for it: posts made, views per post, profile visits, beta sign-ups per
   day, and how many sign-ups were strangers vs people he knows.
3. Anything new: a post that took off, a comment worth answering, a paid test.

If he has no numbers, say so in the report. Never fill a gap with a guess.

## Steps

1. Scripts first: read last week's report in `docs/marketing/weekly/` and the open
   boxes in `growth-plan.md`. There is no script for social numbers; they come from Raj.
2. `scripts/worktree-new.sh grow-<YYYY>-w<NN>`. Keep the path.
3. Spawn `growth` (`subagent_type: growth`). Brief:
   - "Work only in `<path>`. Write only in `docs/marketing/`."
   - "Here are this week's numbers: <numbers>. Write
     `docs/marketing/weekly/<YYYY>-W<NN>.md`: the numbers in a table, the median views,
     the top 20% of posts and their hooks, the formats under the median after 10 posts
     (drop them), the stranger count against the target of 20 before launch, and the
     plan for next week (how many posts, which hooks, batch-made)."
   - "Tick a box in `growth-plan.md` only if the numbers show it is done."
   - "Next week's hooks follow `docs/marketing/brand-voice.md`. Two variants each."
   - "No paid ads until organic shows which hooks convert. Do not commit."
4. Router checks the maths (medians, top 20%) against the numbers Raj gave.
5. Show Raj the report path and the three lines that matter: stranger count, best
   hook, what changes next week.

## Output

`docs/marketing/weekly/<YYYY>-W<NN>.md` and any ticks in `growth-plan.md`, in the
`grow-...` worktree. Commit and PR when Raj says.

## Gate

Raj reads the weekly report. Posting and spending stay his.

## Do not

- Do not post, schedule posts, or buy ads.
- Do not count friends and family as demand. The plan counts strangers only.
- Do not suggest fake reviews, bought followers or engagement pods.
- Do not change the price or the plan's targets without Raj.
