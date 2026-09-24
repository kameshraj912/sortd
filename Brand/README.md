# Sortd brand (locked 19 Sep 2026)

- **Name:** Sortd. Planned App Store name "Sortd Money" / "Sortd: Money Tracker".
  Trademark note: "Get Sortd" is a registered AU mark (no. 2306484, classes 9/35/38) and there is a
  "Sortd – Shopping Wishlist" app in the AU store. Get a trademark opinion before launch. US (USPTO)
  and Singapore (IPOS) registers not yet checked. Domain: sortd.page (bought 19 Sep 2026, Cloudflare).
- **Wordmark:** lowercase "sortd", Inter Tight ExtraBold (800), tight letter-spacing, with a thin
  4-colour bar underneath (orange #F0643D, amber #F5A623, purple #7B6BF0, green #2BB07A).
- **Launch screen:** the wordmark alone (no bar baked in), 64pt, letter-spacing -0.015em, colour
  #16161A light / #E8E8EA dark, on `LaunchBackground` (#F7F7FA / #121214). Sources in
  `icon-source/LaunchWordmark-{Light,Dark}.html` (rendered with Chrome headless, tight-cropped to
  the glyphs — no padding baked in). Asset: `LaunchWordmark.imageset`, referenced by
  `UIImageName` in `Spend-Info.plist`. The bar isn't part of this image: `LaunchOverlay.swift`
  draws it in SwiftUI on top of the same wordmark image so it can animate in on cold start
  (see that file for the exact geometry — 5pt tall pills, 5pt gaps, 9pt below the text, widths
  34/26/20/14pt, centred) without ever differing from the static launch screen's first frame.
- **App icon:** "Colour receipt" — white receipt with torn edge on #111113, four sorted bars in the
  category colours. Flat (iOS adds its own glass). Files: AppIcon.png, AppIcon-Dark.png (transparent
  background), AppIcon-Tinted.png (greyscale, transparent). Sources in icon-source/ (render with Chrome headless at 1024×1024).
- **UI:** black / white / grey; colour only for spending categories.
