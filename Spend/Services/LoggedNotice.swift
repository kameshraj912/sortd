import Foundation
import UserNotifications

/// Sortd's own "Logged" notification after an Apple Pay run (2 Oct 2026).
///
/// The ready-made shortcut runs with "Show When Run" off, so Shortcuts no
/// longer shows the intent's dialog (it waited for Done and later runs
/// queued behind it). This replaces it: one local notification when a tap
/// or Wallet-notification run saves or merges a purchase, only if Sortd
/// already has notification permission. It never asks.
///
/// Sortd's own notification cannot set the shortcut off again: the real
/// shortcut's Notification trigger watches Wallet (`com.apple.Passbook`),
/// not Sortd. (A simulator test build made with
/// `build-apple-pay-shortcut.py --notification-app` must not watch Sortd.)
enum LoggedNotice {
    /// Settings › Purchase Sources › Apple Pay Logging › "Tell me when a
    /// purchase is logged". On by default.
    nonisolated static let enabledKey = "applePayLoggedNotice"

    nonisolated static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Tapping it opens Activity (`NotificationRouter` reads `userInfo["url"]`).
    nonisolated static let url = "sortd://activity"
    private static let idPrefix = "logged-"

    /// What one run left behind, as far as the notice cares.
    enum Saved: Equatable {
        /// A purchase with an amount and a shop.
        case purchase(id: UUID, amount: Decimal, currency: String, merchant: String)
        /// A row tagged "needs a check": no shop, no amount, or neither.
        case needsCheck(id: UUID, missingShop: Bool, missingAmount: Bool)
    }

    struct Content: Equatable {
        /// One per purchase, so a tap and its notification merging into one
        /// row replace the first notice instead of stacking a second.
        let id: String
        let title: String
        let body: String
    }

    /// The run's result in the notice's terms. Nil when nothing was saved
    /// or merged: a ▶ test run, a declined payment, a notification with no
    /// amount, a save that failed and was queued, a refund, a legacy
    /// "Sortd Test" row, or a "Check the Shortcut" run.
    @MainActor
    static func saved(from outcome: LogPurchaseIntent.Outcome) -> Saved? {
        guard !outcome.saveFailed, !outcome.refund, let t = outcome.transaction,
              t.rawMerchant != LogPurchaseIntent.legacyTestMerchant, t.rawMerchant != ApplePayHealthCheck.merchant,
              !t.refunded else { return nil }
        let missingAmount = t.amount <= 0
        let missingShop = t.lacksShop
        if missingAmount || missingShop || t.note.hasPrefix(Transaction.needsCheckTag) {
            return .needsCheck(id: t.id, missingShop: missingShop, missingAmount: missingAmount)
        }
        return .purchase(id: t.id, amount: t.amount, currency: t.currencyCode, merchant: t.merchant)
    }

    /// Post or not, and the words. Pure: the setting and the permission
    /// come in as values.
    @MainActor
    static func content(for saved: Saved?, settingOn: Bool, authorized: Bool) -> Content? {
        guard settingOn, authorized, let saved else { return nil }
        switch saved {
        case .purchase(let id, let amount, let currency, let merchant):
            return Content(id: idPrefix + id.uuidString, title: "Logged",
                           body: "\(Money.format(amount, currency)) at \(merchant)")
        case .needsCheck(let id, let missingShop, let missingAmount):
            let without = switch (missingShop, missingAmount) {
            case (true, true): "a shop or an amount"
            case (false, true): "an amount"
            default: "a shop"
            }
            return Content(id: idPrefix + id.uuidString, title: "Needs a check",
                           body: "A purchase came in without \(without). Tap to fix.")
        }
    }

    /// Whether Sortd may already post. Reads the current setting only.
    static func notificationsAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// After a real run (`LogWalletTapIntent.performAndLog`). Does nothing
    /// unless the setting is on and permission was already given.
    @MainActor
    static func post(for outcome: LogPurchaseIntent.Outcome, defaults: UserDefaults = .standard) async {
        guard isOn(defaults), let saved = saved(from: outcome) else { return }
        guard let content = content(for: saved, settingOn: true, authorized: await notificationsAllowed()) else { return }
        let note = UNMutableNotificationContent()
        note.title = content.title
        note.body = content.body
        note.userInfo = ["url": url]
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: content.id, content: note, trigger: nil))
    }
}
