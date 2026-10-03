import Testing
import Foundation
@testable import Spend

/// 4 Oct 2026, phone run: Get the Shortcut sometimes landed on a page stuck
/// loading, because iOS sent the iCloud link to the default browser. The link
/// now opens only if an app (Shortcuts) takes it; otherwise Sortd shows it in
/// its own Safari sheet, never the default browser.
@MainActor
struct ShortcutLinkTests {

    @Test func anAppThatTakesTheLinkMeansNoSheet() async {
        var asked: [URL] = []
        let sheet = await ShortcutLink.fallback(for: ApplePaySetupSteps.shortcutURL) { url in
            asked.append(url)
            return true
        }
        #expect(sheet == nil)
        #expect(asked == [ApplePaySetupSteps.shortcutURL])
    }

    @Test func noAppTakingTheLinkLeadsToTheSafariSheet() async {
        let sheet = await ShortcutLink.fallback(for: ApplePaySetupSteps.shortcutURL) { _ in false }
        #expect(sheet?.url == ApplePaySetupSteps.shortcutURL)
    }

    @Test func theSheetIsOnlyForWebLinks() async {
        let sheet = await ShortcutLink.fallback(for: URL(string: "shortcuts://")!) { _ in false }
        #expect(sheet == nil)
    }
}
