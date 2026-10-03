# UI pass fixes, 3 Oct 2026

Branch `fix-ui-pass`. Screenshots are in `.build/` (not committed). SE = iPhone SE (3rd generation), iOS 27.

| # | Item | Result | Commit | Screenshot |
|---|------|--------|--------|------------|
| 1 | F1 Where It Went and card tiles at AX5 | Fixed. Reproduced on SE: "De-liv-ery", "$73." / "55", "A..." / "5 pur...". Rows stack at accessibility sizes, tiles are wider and wrap. Activity chips: not a bug (the row scrolls, nothing is cut with "..."); chip text now `lineLimit(1)` + `fixedSize` as a guard. "Scan Receipt" wraps by whole words at AX5 on SE and the button is fully visible: left as is. | 4bbff56 | `f1-before-categories.png`, `f1-after-categories.png`, `f1-before-cards.png`, `f1-after-cards.png`, `f1-before-activity.png`, `f1-after-activity-ax5.png`, `f1-before-add.png` |
| 2 | F4 What's New opens the rating prompt | Not reproduced; could not tap (no tap tool). The only `requestReview` call is the "Rate on the App Store" row, directly above What's New; What's New is a plain `Link`. Most likely a tap on the row above. Link now goes straight to `sortd.page/support#whats-new`. | 6055664 | `f4-before-about.png` |
| 3 | F5 founder note line | Fixed. "That tap you just made..." only for the aha moment; About shows "Thank you for trusting Sortd. Tracking your money should be this easy." Test added. | cf8af4e | none (needs a tap to open) |
| 4 | F6 iCloud switch, no account | Fixed in code: account checked before the switch turns on; line under the switch, switch stays off. Mapping tested. Not seen on screen (needs a tap). | ae7cf74 | `f6-backup.png` (switch off, before tap) |
| 5 | F2 shop name length | Fixed. Logger trims and cuts every source to 80 characters (name and original name); the field cuts a longer paste quietly. Tests. | 1b87b7c, da7f976 | none |
| 6 | F8 amount | Partly not a bug. A second decimal point was already refused (and a third decimal digit), with the "blocked" haptic; the field never shows a digit that was not typed. Test added. Added the "Enter an amount" line under the amount while it is 0 or empty. | da7f976 | `f8-after-add.png`, `f1-after-add.png` |
| 7 | AddTransactionView double save | Fixed. `ManualPurchaseSave` remembers the logged row; a retry updates it. Test: failing re-file then retry leaves one row. | 1b87b7c, da7f976 | none |
| 8 | Paid to above the keypad | Fixed. Paid to and Category sit right under the amount (about 45% down the screen on an iPhone 18 Pro; the number pad starts at about 61%). Scan Receipt and quick entry follow. Checked on SE with the pad up. | da7f976 | `f8-before-add.png`, `f8-after-add.png`, `f1-after-add.png` |

Tests: full `scripts/test.sh` 1206 passed. `--known-bugs`: 55 distinct failing names, all listed in `docs/ux-research/baseline-2026-09-25/README.md`.
