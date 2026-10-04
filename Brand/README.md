# Sortd brand (locked 19 Sep 2026)

- **Name:** Sortd. App Store and website name: "Sortd: Spending Tracker" (since 4 Oct 2026; it was "Sortd Money" on the site before).
  Trademark note: "Get Sortd" is a registered AU mark (no. 2306484, classes 9/35/38) and there is a
  "Sortd – Shopping Wishlist" app in the AU store. Get a trademark opinion before launch. US (USPTO)
  and Singapore (IPOS) registers not yet checked. Domain: sortd.page (bought 19 Sep 2026, Cloudflare).
- **Wordmark:** lowercase "sortd", Inter Tight ExtraBold (800), tight letter-spacing, with a thin
  4-colour bar underneath (orange #F0643D, amber #F5A623, purple #7B6BF0, green #2BB07A).
- **App icon (2 Oct 2026, "A for now"):** a thick white S that reads as a dollar sign (a tick above and
  below) on #111113, over the four-colour bar. The S is the Archivo Black outline, drawn as a path so no
  font is needed. Flat (iOS adds its own glass). Files: AppIcon.png, AppIcon-Dark.png (transparent
  background), AppIcon-Tinted.png (greyscale, transparent). Sources in icon-source/ (render with Chrome
  headless at 1024×1024; transparent ones need `--default-background-color=00000000`).
  Before it: "Colour receipt", a white receipt with four sorted bars (19 Sep to 2 Oct 2026).
  Still to change outside the app: site/img and launch/ icons, the App Store Connect 1024 px upload,
  the Instagram avatar, and any screenshot that shows the Home Screen.
- **UI:** black / white / grey; colour only for spending categories.

## Layered app icon (Icon Composer, 25 Sep 2026)

`Spend/AppIcon-Glass.icon` is the same mark as a layered Icon Composer
package: `icon.json` plus `Assets/mark.svg` (the S and its ticks) and `Assets/bar.svg` (the four dashes),
the same shapes as `icon-source/AppIcon.html`. Background is a solid #111113 fill.
Dark, clear and tinted come from Icon Composer's appearance handling, not from separate
images. Open it with Xcode > Open Developer Tool > Icon Composer to tune glass, specular
and shadow. In `icon.json` the first group is the frontmost.

**Active since 25 Sep 2026** (branch `flags-on`): both `ASSETCATALOG_COMPILER_APPICON_NAME`
lines in `Spend.xcodeproj/project.pbxproj` (Debug and Release of the Spend target; the widget
target is untouched) point at `"AppIcon-Glass"`. Pending Raj's look on the phone in light,
dark, clear and tinted, and CI green on the pinned Xcode 26.6. `AppIcon.appiconset` (flat
PNGs) stays in the catalog until then. A `.icon` with the same name as the appiconset
silently wins with no warning, which is why this one is not called `AppIcon.icon`.

Once Raj has approved it on the phone and CI is green: `git mv Spend/AppIcon-Glass.icon
Spend/AppIcon.icon`, set the setting back to `AppIcon`, and delete
`Spend/Assets.xcassets/AppIcon.appiconset` (Apple: a `.icon` replaces the catalog icon;
Xcode renders the pre-26 fallback PNGs from it).

To revert: put both `ASSETCATALOG_COMPILER_APPICON_NAME` lines back to `AppIcon`. Nothing
else changes; the flat PNGs are still in the catalog.
