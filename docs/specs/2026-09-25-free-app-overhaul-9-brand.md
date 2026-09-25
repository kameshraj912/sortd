# Overhaul 9: icons and branded assets (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj: "Custom icons and branded assets."

**What exists (checked):**
- App icon light, dark and tinted as flat PNGs, with luminosity appearances (`Spend/Assets.xcassets/AppIcon.appiconset/Contents.json`), sources in `Brand/icon-source/*.html`.
- `BrandIcon` (setup welcome), `LaunchWordmark` light and dark, `LaunchBackground`, `GoogleG`.
- The wordmark and colours are locked (`Brand/README.md`).

**What is missing:**
- A layered Icon Composer icon, so iOS 26 can apply Liquid Glass, clear and tinted properly (`HANDOVER.md` still-to-do 5).
- A widget accented-rendering check (same list).
- Any mascot art (heyclicky reference).
- App Store screenshots: 6.9" 1320×2868, 1–10 of them (`docs/AppStoreChecklist.md`).

Tabs and categories use SF Symbols (`AppTab.symbol`, `SpendCategory`).

## Options

| | A. Layered icon + screenshots, keep SF Symbols (recommended) | B. A + custom symbol set for tabs and categories | C. A + choice of app icons in Settings |
|---|---|---|---|
| Work | 3 d, mostly design | +5 d | +1 d |
| HIG fit | system glyphs scale, bold and localise | custom symbols must be SF Symbol templates to scale (**not verified**) | fine |
| Risk | low | tab icons stop matching the system | small |

## Recommendation

A.
- Build `AppIcon.icon` in Icon Composer from the existing receipt and bars layers.
- Keep SF Symbols in the UI. Consider one custom symbol only: the receipt mark, as an SF Symbol template, for empty states and the aha card.
- Screenshots: a three-phone hero (Flighty reference), one short line per screen, dark and light, on 6.9". No award badges until we have real ones.
- Mascot: the receipt icon with 3–4 expressions, once Raj draws them. Copy-only until then (overview question 10).

First step: the `.icon` file and a check on a real home screen in every appearance.

**Status (25 Sep 2026):** `Spend/AppIcon-Glass.icon` is the active icon
(`ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-Glass"` in both Spend target configs, branch
`flags-on`). Pending Raj's look on the phone in every appearance and CI on Xcode 26.6.
`AppIcon.appiconset` stays until then; `Brand/README.md` says how to revert.

## Files

- `Spend/AppIcon-Glass.icon` (Icon Composer), selected by `ASSETCATALOG_COMPILER_APPICON_NAME` in `Spend.xcodeproj/project.pbxproj` (two lines, Spend target only; folder sync does not cover this setting).
- `Spend/Assets.xcassets/AppIcon.appiconset/`: keep until the `.icon` is proven on the phone and on CI's pinned Xcode 26.6.
- `Brand/`, `Brand/README.md`.
- `SortdWidget/SortdWidget.swift`: accented rendering.
- Screenshots: `docs/AppStoreListing.md` (router or growth).

## Test plan

- Test: `UIImage(named: "BrandIcon")` and `UIImage(named: "LaunchWordmark")` are not nil (asset rename guard).
- Build check: `scripts/build.sh` passes on local Xcode 27 (checked 25 Sep 2026 with the `.icon` active), and CI passes on pinned Xcode 26.6 with the `.icon` file. **Not verified** that 26.6 builds `.icon`; Icon Composer shipped with Xcode 26.
- `ui-driver`:
  - home screen icon in light, dark, tinted and clear;
  - widget in accented mode;
  - wordmark at launch in both schemes;
  - screenshots at 1320×2868.
- Device only: how the glass icon looks on a real home screen.

## Gate

- Raj approves the icon renders and the screenshot set.
- CI is green on the pinned Xcode.

## Sources (read 25 Sep 2026)

- [WWDC25: Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/) (search summary; video not watched)
- [Adding Icon Composer icons to Xcode](https://useyourloaf.com/blog/adding-icon-composer-icons-to-xcode/)
- `docs/ux-research/07` (Flighty, heyclicky)
