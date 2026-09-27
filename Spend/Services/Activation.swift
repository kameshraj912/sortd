import Foundation
import SwiftData

/// The aha moment (overhaul sub-spec 6): the first purchase Sortd logged by
/// itself, from an Apple Pay tap or a Gmail receipt. Sample data and a
/// legacy "Send a Test Tap" purchase (`LogPurchaseIntent.legacyTestMerchant`,
/// the test button was removed 25 Sep 2026) never count: they prove nothing
/// about the person's own spending.
///
/// Pure detection plus two once-only flags in UserDefaults. Home reads the
/// flags and shows the card; nothing here draws anything or asks for a
/// permission. `watchSaves` is the one hook, on the same `didSave` the
/// widget and iCloud backup use, so the logger stays free of it.
enum Activation {
    enum Source: String { case tap, email }

    /// Set once, when the first qualifying purchase is saved.
    static let seenKey = "activationSeen"
    /// Set once the person has answered the single notification ask on
    /// Home (yes or no). Declined means never asked again.
    static let askedKey = "notificationAskShown"
    /// The aha card's haptic and tick have played: once per install, not
    /// once per launch while the ask is still up.
    static let celebratedKey = "activationCelebrated"

    /// Which automatic source this purchase came from, or nil when it does
    /// not count as the aha.
    static func detect(_ t: Transaction) -> Source? {
        guard t.note != DemoData.marker else { return nil }
        guard t.merchant != LogPurchaseIntent.legacyTestMerchant, t.rawMerchant != LogPurchaseIntent.legacyTestMerchant else { return nil }
        guard t.merchant != ApplePayHealthCheck.merchant, t.rawMerchant != ApplePayHealthCheck.merchant else { return nil }
        // A refund proves nothing about the person's own spending -- and a
        // standalone refund tap (no earlier purchase to match) would
        // otherwise become its own row and wrongly trigger the aha.
        guard !t.refunded else { return nil }
        // A flagged "needs a check" row (spec 2026-09-26, failsafes #10/#13)
        // is a tap that arrived with too little to log cleanly — it proves
        // Sortd is connected, not that the person has real spending to see,
        // so it must never be the aha and must never spend the one
        // celebration a real first purchase gets.
        guard !t.needsCheck else { return nil }
        let seen = t.seenIn
        if seen.contains(.tap) { return .tap }
        if seen.contains(.email) { return .email }
        return nil
    }

    /// Records the aha once per install. Returns the source the first time a
    /// qualifying purchase is seen, nil for every call after (and for any
    /// purchase that does not qualify).
    @discardableResult
    static func recordIfFirst(_ t: Transaction, defaults: UserDefaults = .standard) -> Source? {
        guard let source = detect(t), !defaults.bool(forKey: seenKey) else { return nil }
        defaults.set(true, forKey: seenKey)
        return source
    }

    /// The one notification ask comes after the aha and only until answered.
    static func shouldAskForNotifications(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: seenKey) && !defaults.bool(forKey: askedKey)
    }

    static func markNotificationAsked(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }

    // MARK: - Existing installs

    /// Set the first time a build that has Activation runs.
    static let knownKey = "activationKnown"

    /// Once, at the first launch of a build with Activation: an install that
    /// had already finished setup was asked about notifications by the old
    /// check-in step and may hold tap rows for weeks. It never gets the
    /// card or a second ask. A fresh install (setup not done yet) is left
    /// open, and later launches change nothing.
    static func settleExistingInstall(setupDone: Bool, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: knownKey) else { return }
        defaults.set(true, forKey: knownKey)
        guard setupDone else { return }
        defaults.set(true, forKey: seenKey)
        defaults.set(true, forKey: askedKey)
    }

    // MARK: - Hook

    /// When this process started. A row made before it (a restore keeps the
    /// original `createdAt`, Backup.swift) was not logged now.
    static let launchedAt = Date.now

    /// After every save to the store, until the aha has happened: look at
    /// the rows that save inserted. Call once at launch. Off under the
    /// old-setup escape, like the card it feeds.
    @MainActor
    static func watchSaves() {
        guard SetupFlow.usesNewFlow, !UserDefaults.standard.bool(forKey: seenKey) else { return }
        let context = SpendStore.container.mainContext
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { note in
            // `_ =` and the explicit Void: Xcode 26.6's Swift cannot infer
            // assumeIsolated's T when the closure's single expression returns
            // a value (Swift 6.4 can), and CI pins Xcode 26.6.
            MainActor.assumeIsolated { () -> Void in
                _ = check(inserted: inserted(in: note, context: context), since: launchedAt)
            }
        }
    }

    /// The `Transaction` rows a `didSave` inserted (edits and deletes carry
    /// none, so they cost nothing here).
    @MainActor
    static func inserted(in note: Notification, context: ModelContext) -> [Transaction] {
        let key = ModelContext.NotificationKey.insertedIdentifiers
        let ids = (note.userInfo?[key] ?? note.userInfo?[key.rawValue]) as? [PersistentIdentifier] ?? []
        return ids.compactMap { context.model(for: $0) as? Transaction }
    }

    /// `recordIfFirst` on each inserted row made in this launch, in order.
    /// A restored or imported row (older `createdAt`) never counts; a
    /// no-op once the flag is set.
    @discardableResult
    static func check(inserted: [Transaction], since launch: Date, defaults: UserDefaults = .standard) -> Source? {
        guard !defaults.bool(forKey: seenKey) else { return nil }
        for t in inserted where t.createdAt >= launch {
            if let source = recordIfFirst(t, defaults: defaults) { return source }
        }
        return nil
    }
}
