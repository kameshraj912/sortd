# Sortd iOS Polish Checklist
Researched from Apple's own guidelines plus practitioner write-ups (marked "practitioner"). Sources cited by short label, full URLs + date read at the bottom. ★ = 10 items most likely wrong in a young SwiftUI app.

## Layout and spacing
1. ★ Compare card/row padding to the system's 16pt standard margin — inspect in Xcode's View Debugger, don't eyeball. [HIG-Layout]
2. Check spacing uses 8pt-grid multiples (4/8/12/16/24) — grep `.padding(` values in code. [HIG-Layout]
3. Confirm content clears the safe area / Dynamic Island on 17 Pro Max, portrait and landscape, in Simulator. [HIG-Layout]
4. Check the glass tab bar/toolbar isn't crowded — NN/g found iOS 26 tab bars "bunched together." [NNg]

## Typography and Dynamic Type
5. ★ Test every screen at accessibility size AX5 (Settings > Accessibility > Display & Text Size) for truncation/overlap. [HIG-Type]
6. Confirm text uses system text styles (`.body`, `.headline`) not fixed sizes — grep `.font(.system(size:`. [HIG-Type]
7. Check no label drops below 11pt (Caption) even at the smallest Dynamic Type setting. [HIG-Type]
8. Verify currency figures and category names scale without clipping inside Liquid Glass cards. [HIG-Type]

## Navigation, titles and search
9. Confirm the large title collapses to inline on scroll, on every tab, with no jump or flicker. [HIG-Nav]
10. Check the pull-down search placeholder names what's searchable ("Search merchants, categories"), not just "Search." [HIG-Search]
11. Verify each nav bar has no more than title + back + one control, per HIG's crowding rule. [HIG-Nav]
12. Check the search field doesn't fade into a glass background — NN/g flagged its "pale design... fades into the background" in iOS 26. [NNg]

## Touch targets and controls
13. ★ Measure every tappable control (tip presets, category chips, swipe actions) at ≥44×44pt in the View Debugger. [HIG-Layout]
14. Check ≥8pt gap between adjacent controls — NN/g found iOS 26 apps violating the old 0.4cm spacing rule. [NNg]
15. Verify glass buttons stay tappable, not just visible, when partly scrolled under the nav/tab bar. [HIG-Layout]
16. Test one-handed reach of the primary "add spend" action on Pro Max in Simulator.

## Sheets, alerts, confirmations
17. Check add/edit-spend sheets confirm before discarding unsaved edits on swipe-to-dismiss. [HIG-Sheets]
18. Verify alerts use at most 2–3 buttons, most-likely choice trailing/top, Cancel leading/bottom. [HIG-Alerts]
19. Confirm destructive actions (delete transaction, reset data) always pair with a Cancel option. [HIG-Alerts]
20. Check alert titles state what happened plainly — no bare "Error" or vague titles. [HIG-Alerts]

## Onboarding and first run
21. ★ Verify the three-step intro overlay is skippable, per HIG's "fast, fun and optional" onboarding rule. [HIG-Onboarding]
22. Check a user can log a spend before finishing all three intro steps — onboarding shouldn't gate use. [HIG-Onboarding]
23. Confirm permission prompts (Gmail, notifications) fire in-context, not bundled into the intro overlay upfront. [HIG-Onboarding][AppReview]
24. Test that TipKit tips don't stack or overlap with the intro overlay on first launch.

## Empty, loading and error states
25. ★ Check the zero-transactions empty state gives real guidance/CTA, not a blank screen — NN/g-cited data found 92% of AI-built empty states missing entirely. [RawStudio]
26. Verify Gmail receipt sync shows a loading indicator, not a frozen list, while fetching. [RawStudio]
27. Check a Gmail-auth or network failure surfaces a specific, actionable error, not a generic alert. [RawStudio]
28. Confirm a no-results search state explains "no matches" rather than showing an empty list. [HIG-Search]

## Motion and haptics
29. Test key screens with Reduce Motion on — animations should shorten or cross-fade, not run full-motion. [HIG-A11y]
30. ★ Check Liquid Glass specular/parallax effects respect Reduce Motion and Reduce Transparency toggles. [HIG-LiquidGlass]
31. Verify haptics use system-defined patterns (success/error/selection) consistently, e.g. on tip confirmation. [HIG-Haptics]
32. Check haptics fire on discrete actions only, not on every scroll or list update. [HIG-Haptics]

## Accessibility
33. ★ Run VoiceOver (triple-click side button) over every screen — every icon-only button (delete, tab icons, tip presets) needs a real label, not "button." [HIG-A11y]
34. Check text/glyph contrast on glass surfaces meets 4.5:1 (body) / 3:1 (large text). [HIG-A11y]
35. Verify category colors aren't the only signal for colorblind users — pair color with icon or label. [HIG-A11y]
36. Fill in the App Store Connect Accessibility Nutrition Label accurately before submission. [Apple-A11yLabel]

## Copy and tone
37. Check "tip jar" (in-app purchase) and "TipKit tips" (coach marks) are never confused in UI copy — same word, two features.
38. Verify error/empty-state copy is specific and human, not "Something went wrong." [RawStudio]
39. Check search placeholder text names what's searchable rather than just saying "Search." [HIG-Search]

## Privacy, permissions and App Review
40. ★ Confirm the Gmail OAuth purpose string and in-app explanation appear before the system prompt, and consent is revocable. [AppReview 5.1.1(ii)]
41. Check whether Gmail sign-in counts as primary-account setup — if so, an equivalent Sign in with Apple option is required. [AppReview 4.8]
42. Verify Sentry/PostHog data collection is disclosed accurately in the App Privacy (nutrition) labels, matching what they actually collect. [AppReview 5.1.1(i)]
43. Confirm no App Tracking Transparency prompt appears unless cross-app/site tracking actually happens — first-party analytics don't require it. [AppReview 5.1.2(i)]
44. ★ Test the tip jar as a real consumable in-app purchase in the App Store Connect sandbox before submitting — Apple explicitly allows IAP for developer tips. [AppReview 3.1.1]
45. Check the app has a working path with no Gmail account connected — reviewers may not link one; no dead ends. [AppReview 2.1(a)]
46. Verify a privacy policy URL is set in App Store Connect and reachable from inside the app. [AppReview 5.1.1(i)]
47. Confirm the app doesn't crash in the first 60 seconds on an older/base-model device. [QAwerk, practitioner]

## Performance and polish
48. Check SwiftData fetches on the spending list don't block the main thread with large receipt histories — profile with Instruments.
49. ★ Confirm Liquid Glass blur/refraction doesn't tank scroll FPS on older supported devices — profile in Instruments. [HIG-LiquidGlass]
50. Verify App Store Connect screenshots match the live Liquid Glass UI, not a stale pre-iOS 26 look. [AppReview 2.3.1]

---

## ★ Top 10 most likely to be wrong in a young SwiftUI app
1. Card/row padding not actually at the 16pt standard margin (#1)
2. Screens breaking at Dynamic Type AX5 (#5)
3. Controls under 44×44pt, especially chips/presets (#13)
4. Intro overlay not skippable (#21)
5. No real empty state for zero transactions (#25)
6. Liquid Glass motion ignoring Reduce Motion/Reduce Transparency (#30)
7. Icon-only buttons missing VoiceOver labels (#33)
8. Gmail OAuth consent shown without an in-app purpose explanation first (#40)
9. Tip jar never tested as a real sandboxed IAP before submission (#44)
10. Liquid Glass effects tanking scroll performance on older devices (#49)

---

## Sources (cite label → URL, date read: 2026-09-25)
- [HIG-Layout] Apple, Human Interface Guidelines — Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- [HIG-Type] Apple, Human Interface Guidelines — Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- [HIG-Nav] Apple, Human Interface Guidelines — Navigation and search: https://developer.apple.com/design/human-interface-guidelines/navigation-and-search
- [HIG-Search] Apple, Human Interface Guidelines — Search fields: https://developer.apple.com/design/human-interface-guidelines/search-fields
- [HIG-Sheets] Apple, Human Interface Guidelines — Sheets: https://developer.apple.com/design/human-interface-guidelines/sheets
- [HIG-Alerts] Apple, Human Interface Guidelines — Alerts: https://developer.apple.com/design/human-interface-guidelines/alerts
- [HIG-Onboarding] Apple, Human Interface Guidelines — Onboarding: https://developer.apple.com/design/human-interface-guidelines/onboarding
- [HIG-Haptics] Apple, Human Interface Guidelines — Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- [HIG-A11y] Apple, Human Interface Guidelines — Accessibility foundations: https://developer.apple.com/design/human-interface-guidelines/foundations/accessibility
- [HIG-LiquidGlass] Apple Newsroom, "Apple introduces a delightful and elegant new software design" (9 Jun 2025): https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ ; Apple HIG Liquid Glass foundations: https://developer.apple.com/design/human-interface-guidelines
- [Apple-A11yLabel] Apple, App Store Connect Help — Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- [AppReview] Apple, App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/ (guideline numbers 2.1, 2.3, 3.1.1, 4.2, 5.1.1, 5.1.2 fetched directly; 4.8 "Sign in with Apple" confirmed via Apple Developer Forums threads, not directly quoted from the guidelines page in this session)
- [NNg] Nielsen Norman Group, "Liquid Glass Is Cracked, and Usability Suffers in iOS 26" (practitioner review, published 10 Oct 2025): https://www.nngroup.com/articles/liquid-glass/
- [RawStudio] Raw.Studio blog, "Empty States, Error States & Onboarding: The Hidden UX Moments Users Notice" (practitioner write-up): https://raw.studio/blog/empty-states-error-states-onboarding-the-hidden-ux-moments-users-notice/
- [QAwerk] QAwerk blog, "App Store Rejection Reasons in 2026" (practitioner write-up, published 14 May 2026): https://qawerk.com/blog/app-store-rejection-reasons/
