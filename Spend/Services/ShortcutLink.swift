import Foundation

/// The ready-made "Log to Sortd" shortcut, shared from iCloud. When it's set,
/// setup offers it: one tap adds it, and the Wallet automation just runs it,
/// so nobody has to fill in Amount / Merchant / Card by hand.
///
/// To make the link: build the shortcut on an iPhone with Sortd installed
/// (Receive Wallet input → Log Purchase with Amount, Merchant, Card from the
/// Shortcut Input), then Share → Copy iCloud Link, and paste it below.
enum ShortcutLink {
    static let url: URL? = nil
}
