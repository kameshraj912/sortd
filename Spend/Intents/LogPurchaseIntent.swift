import AppIntents
import SwiftData

/// Called by the Shortcuts "Transaction" automation every time Raj taps a
/// card in Wallet. Runs in the background; the app does not open.
struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase"
    static let description = IntentDescription(
        "Adds a purchase to Sortd. Use it in a Wallet automation so every Apple Pay tap is logged.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Merchant", description: "Shop name. In the automation, pick the Merchant variable.")
    var merchant: String?

    @Parameter(title: "Amount", description: "In the automation, pick the Amount variable. Text like “A$4.50” is fine.")
    var amount: String?

    @Parameter(title: "Card", description: "In the automation, pick the Wallet transaction, then Card or Pass.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        // All three on one line, so none is hidden under "Show More".
        Summary("Log \(\.$amount) at \(\.$merchant) on \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // #8 (spec 2026-09-26): if the store itself can't open, never crash
        // the process the way touching `SpendStore.container` directly
        // could — queue the raw tap instead.
        guard case .success(let container) = SpendStore.containerForIntent() else {
            let message = await TapQueue.saveForLater(merchant: merchant, amount: amount, card: card)
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        let result = try await Self.handle(merchant: merchant, amount: amount, card: card,
                                           in: container.mainContext, book: .shared)
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }

    /// What happened to one tap. `transaction` is nil for an empty test run,
    /// or when the save itself failed (`saveFailed`) and the raw fields
    /// were queued instead — never for an ordinary logged purchase.
    struct Outcome {
        let message: String
        let transaction: Transaction?
        let merged: Bool
        var saveFailed: Bool = false
    }

    /// The merchant name the removed "Send a Test Tap" button wrote
    /// (`Spend/Views/Components/TapTestButton.swift`, deleted 25 Sep 2026).
    /// Kept as a constant, not deleted rows: old installs may still have
    /// test purchases under this name, and they must stay excluded from
    /// activation, suggestions and the Apple Pay status.
    nonisolated static let legacyTestMerchant = "Sortd Test"

    static let lastTapKey = "lastTapReceived"

    /// When Shortcuts last reached Sortd at all — including a ▶ test run that
    /// carried no purchase. Setup uses it to tell "not set up yet" apart from
    /// "set up, waiting for a real tap", which look the same from the
    /// transaction list alone.
    static let lastTapAtKey = "lastTapReceivedAt"

    /// True once Shortcuts has reached the app, whether or not it logged.
    static var shortcutHasReachedApp: Bool {
        UserDefaults.standard.object(forKey: lastTapAtKey) != nil
    }

    /// When Shortcuts last reached the app, for the Apple Pay status line.
    static var lastTapReceivedAt: Date? {
        UserDefaults.standard.object(forKey: lastTapAtKey) as? Date
    }

    /// A tap counts as the first auto-logged purchase only when it was
    /// added (not merged) and is not a legacy "Send a Test Tap" purchase.
    nonisolated static func countsAsActivation(added: Bool, merchant: String) -> Bool {
        added && merchant != legacyTestMerchant
    }

    /// The whole tap-handling logic, callable from tests.
    @MainActor
    static func handle(merchant: String?, amount: String?, card: String?,
                       in context: ModelContext, book: CardBook, now: Date = .now,
                       debugForceSaveFailure: Bool = false) async throws -> Outcome {
        // Shortcuts sometimes hands intents an empty merchant or amount
        // (developer.apple.com/forums/thread/797233). Never drop a real tap:
        // save it with amount 0 and flag it so it can be filled in.
        let parsed = AmountParser.parse(amount ?? "")
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing at all came in: a test run (the ▶ button in Shortcuts),
        // not a Wallet tap. Don't save an empty purchase.
        let cardName = (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep exactly what arrived, for checking the setup (Settings shows it).
        let seen = "amount “\(amount ?? "")” · merchant “\(merchant ?? "")” · card “\(card ?? "")”"
        UserDefaults.standard.set("\(now.formatted(date: .abbreviated, time: .standard)): \(seen)", forKey: lastTapKey)
        UserDefaults.standard.set(now, forKey: lastTapAtKey)
        UserDefaults.standard.synchronize()
        // Nothing at all came in — not even a card: a bare ▶ run in
        // Shortcuts, not a Wallet tap. Nothing is saved. A card name alone
        // (no amount, no shop) is different: that's a real automation run
        // that only supplied a card, and known bug U6 used to save that
        // card name as if it were the shop. It's kept below, tagged "needs
        // a check", instead of either extreme.
        if name.isEmpty, parsed == nil, cardName.isEmpty {
            return Outcome(message: "Sortd is connected. Test runs don't include a purchase — pay with Apple Pay in a shop to log one.",
                           transaction: nil, merged: false)
        }
        let missingAmount = parsed == nil || parsed!.amount == 0
        let missingShop = name.isEmpty
        let refund = AmountParser.isNegative(amount ?? "")
        let cardID = book.matchOrCreate(card)

        // #8 (spec 2026-09-26): never let a throw from here on — a fetch or
        // a save failing (disk full, corrupt file, failed migration) —
        // propagate out of the intent. Queue the raw fields instead and
        // tell Shortcuts (and the person) it will be finished later.
        do {
            // Test-only seam (`debugForceSaveFailure`, default false, never
            // set outside `SpendTests`): behaves exactly as if
            // `context.save()` below had thrown, without needing a
            // genuinely broken disk to prove it — a plain parameter, not
            // shared mutable state, so parallel tests can't race on it
            // (spec 2026-09-26, failsafe #8; see `ThrowSafetyTests`).
            if debugForceSaveFailure { throw CocoaError(.fileWriteUnknown) }
            // A second tap with no amount at the same shop within 2 minutes is
            // the same purchase (the Deduper can't match on a missing amount).
            if missingAmount {
                let since = now.addingTimeInterval(-120)
                let shop = name.isEmpty ? "Unknown merchant" : name
                let recent = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since }))
                // `merchant` is the cleaned name ("SQ *CAFE X" → "Cafe X"); the
                // tap's own text is kept in `rawMerchant`, so compare that.
                if let same = recent.first(where: { $0.amount == 0 && $0.rawMerchant == shop && $0.card == cardID }) {
                    return Outcome(message: "That purchase at \(shop) is already in Sortd — open it to add the amount", transaction: same, merged: true)
                }
            }
            // A refund tap: mark the purchase it belongs to as refunded, so the
            // total goes down. Refunds can take weeks, so look back 60 days.
            if refund, let p = parsed, p.amount > 0 {
                let currency = p.currency ?? LocalCurrency.current()
                if EmailSync.markRefunded(amount: p.amount, currency: currency, card: cardID, merchant: name,
                                          platform: nil, before: now, lookbackDays: 60, in: context) {
                    try context.save()
                    return Outcome(message: "Refund of \(Money.format(p.amount, currency)) from \(name.isEmpty ? "the shop" : name) noted — the purchase no longer counts",
                                   transaction: nil, merged: true)
                }
                // No whole purchase matches: maybe this refund is only part of a
                // bigger one (one returned item from a A$59.90 basket).
                if let reduced = EmailSync.markPartiallyRefunded(amount: p.amount, currency: currency, card: cardID,
                                                                 merchant: name, platform: nil, before: now,
                                                                 lookbackDays: 60, in: context) {
                    try context.save()
                    await FXService.backfill(in: context)
                    let shop = reduced.merchant.isEmpty ? (name.isEmpty ? "the shop" : name) : reduced.merchant
                    return Outcome(message: "\(Money.format(p.amount, currency)) refund on \(shop) noted",
                                   transaction: reduced, merged: true)
                }
            }
            // "needs a check" (spec item 2/10): a blank amount, a blank shop,
            // or a card with neither — each tagged distinctly, but always
            // kept as a row, never dropped.
            let note: String
            if missingAmount, missingShop, !cardName.isEmpty {
                note = "\(Transaction.needsCheckTag)Apple Pay sent only a card (\(seen)). Tap to fix."
            } else if missingAmount {
                note = "\(Transaction.needsCheckTag)Apple Pay sent no amount (\(seen)). Tap to fix."
            } else if missingShop {
                note = "\(Transaction.needsCheckTag)Apple Pay sent no shop name (\(seen)). Tap to fix."
            } else {
                note = refund ? "Refund to your card" : ""
            }
            let purchase = IncomingPurchase(
                date: now,
                merchant: name.isEmpty ? "Unknown merchant" : name,
                amount: parsed?.amount ?? 0,
                currency: parsed?.currency ?? LocalCurrency.current(),
                card: cardID,
                source: .tap,
                note: note
            )

            let outcome = try TransactionLogger.log(purchase, in: context)
            let t = outcome.transaction
            // A standalone refund tap (no earlier purchase to match) becomes its
            // own row here. It proves nothing about the person's own spending,
            // so this returns before the activation event below ever sees it.
            if refund, !t.refunded {
                t.refunded = true
                try context.save()
                return Outcome(message: "Refund of \(Money.format(t.amount, t.currencyCode)) from \(t.merchant) noted", transaction: t, merged: false)
            }
            // The first purchase the app logged on its own (once per install).
            // A "Send a Test Tap" purchase is not one.
            if case .added = outcome, Self.countsAsActivation(added: true, merchant: name) {
                Analytics.shared.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
            }
            await FXService.backfill(in: context)

            if missingAmount, missingShop, !cardName.isEmpty {
                return Outcome(message: "Tap noted — only got a card, no shop or amount. Add it in Sortd.", transaction: t, merged: false)
            }
            if missingAmount {
                return Outcome(message: "Tap noted, amount missing. Add it in Sortd.", transaction: t, merged: false)
            }
            if missingShop {
                return Outcome(message: "Tap noted, shop missing. Add it in Sortd.", transaction: t, merged: false)
            }
            let money = Money.format(t.amount, t.currencyCode)
            switch outcome {
            case .added:
                return Outcome(message: "Logged \(money) at \(t.merchant) · \(t.category.name)", transaction: t, merged: false)
            case .merged:
                return Outcome(message: "\(money) at \(t.merchant) was already logged", transaction: t, merged: true)
            }
        } catch {
            let message = await TapQueue.saveForLater(merchant: merchant, amount: amount, card: card, date: now)
            return Outcome(message: message, transaction: nil, merged: false, saveFailed: true)
        }
    }
}

struct SpendShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: ["Log a purchase in \(.applicationName)", "Add spending to \(.applicationName)"],
            shortTitle: "Log Purchase",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: LogWalletTapIntent(),
            phrases: ["Log a Wallet tap in \(.applicationName)"],
            shortTitle: "Log Wallet Tap",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: SpentThisPeriodIntent(),
            phrases: [
                "How much have I spent in \(.applicationName)",
                "How much have I spent \(\.$period) in \(.applicationName)",
                "What have I spent \(\.$period) in \(.applicationName)",
                "Ask \(.applicationName) how much I spent \(\.$period)",
            ],
            shortTitle: "Amount Spent",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: BudgetLeftIntent(),
            phrases: [
                "How much budget is left in \(.applicationName)",
                "What's left of my budget in \(.applicationName)",
                "Ask \(.applicationName) how much budget I have left",
            ],
            shortTitle: "Budget Left",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: UpcomingBillsIntent(),
            phrases: [
                "What bills are coming up in \(.applicationName)",
                "Show upcoming bills in \(.applicationName)",
                "Ask \(.applicationName) what bills are due",
            ],
            shortTitle: "Upcoming Bills",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: LastPurchaseIntent(),
            phrases: [
                "What was my last purchase in \(.applicationName)",
                "Show my last purchase in \(.applicationName)",
                "Ask \(.applicationName) what I bought last",
            ],
            shortTitle: "Last Purchase",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
