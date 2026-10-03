import SwiftUI
import SafariServices
import UIKit

/// Opening the Get the Shortcut link. It is an https iCloud link that the
/// Shortcuts app should take. If iOS hands it to the default browser instead,
/// the page can sit loading for ever (4 Oct 2026, Chrome). So the link opens
/// as a universal link only: an app takes it, or nothing does and Sortd shows
/// the same page in its own Safari sheet.
enum ShortcutLink {
    /// Opens a URL and says whether an app took it.
    typealias Opener = @MainActor (URL) async -> Bool

    /// The real opener: universal links only, so the default browser is never used.
    static let universalLinksOnly: Opener = { url in
        await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
    }

    /// Tries `url` with `opener`. Nil when an app took it; otherwise the
    /// Safari sheet to show (web links only: a Safari sheet can't open
    /// anything else).
    @MainActor
    static func fallback(for url: URL, opener: Opener = ShortcutLink.universalLinksOnly) async -> SafariPage? {
        if await opener(url) { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return SafariPage(url: url)
    }
}

/// A web page to show in the in-app Safari sheet.
struct SafariPage: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

/// `SFSafariViewController` as a sheet's content.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
