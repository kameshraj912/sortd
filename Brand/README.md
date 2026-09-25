# Sortd brand (locked 19 Sep 2026)

- **Name:** Sortd. Planned App Store name "Sortd Money" / "Sortd: Money Tracker".
  Trademark note: "Get Sortd" is a registered AU mark (no. 2306484, classes 9/35/38) and there is a
  "Sortd – Shopping Wishlist" app in the AU store. Get a trademark opinion before launch. US (USPTO)
  and Singapore (IPOS) registers not yet checked. Domain: sortd.page (bought 19 Sep 2026, Cloudflare).
- **Wordmark:** lowercase "sortd", Inter Tight ExtraBold (800), tight letter-spacing, with a thin
  4-colour bar underneath (orange #F0643D, amber #F5A623, purple #7B6BF0, green #2BB07A).
- **App icon:** "Colour receipt" — white receipt with torn edge on #111113, four sorted bars in the
  category colours. Flat (iOS adds its own glass). Files: AppIcon.png, AppIcon-Dark.png (transparent
  background), AppIcon-Tinted.png (greyscale, transparent). Sources in icon-source/ (render with Chrome headless at 1024×1024).
- **UI:** black / white / grey; colour only for spending categories.

## Layered app icon (Icon Composer, 25 Sep 2026)

`Spend/AppIcon-Glass.icon` is the same receipt and bars as a layered Icon Composer
package: `icon.json` plus `Assets/receipt.svg` and `Assets/bars.svg` (hand-exported from
`icon-source/AppIcon.html`, same 0.66 transform). Background is a solid #111113 fill.
Dark, clear and tinted come from Icon Composer's appearance handling, not from separate
images. Open it with Xcode > Open Developer Tool > Icon Composer to tune glass, specular
and shadow. In `icon.json` the first group is the frontmost.

**It is not the active icon yet.** `AppIcon.appiconset` (flat PNGs) stays active until CI on
the pinned Xcode 26.6 has built the package. Xcode 27 builds it (checked 25 Sep 2026).
A `.icon` with the same name as the appiconset silently wins with no warning, which is why
this one is not called `AppIcon.icon`.

To switch (one setting, two places):

1. In `Spend.xcodeproj/project.pbxproj`, change both `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`
   lines (Debug and Release of the Spend target) to `ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-Glass";`.
2. `scripts/build.sh`, then install on the simulator and check the Home Screen in light,
   dark, clear and tinted.
3. Push and wait for CI (Xcode 26.6) to go green.
4. Only then: `git mv Spend/AppIcon-Glass.icon Spend/AppIcon.icon`, set the setting back to
   `AppIcon`, and delete `Spend/Assets.xcassets/AppIcon.appiconset` (Apple: a `.icon` replaces
   the catalog icon; Xcode renders the pre-26 fallback PNGs from it).

To revert: put the setting back to `AppIcon`. Nothing else changes.
