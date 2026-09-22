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
        let result = try await Self.handle(merchant: merchant, amount: amount, card: card,
                                           in: SpendStore.container.mainContext, book: .shared)
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: SpendStore.container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }

    /// What happened to one tap. `transaction` is nil for an empty test run.
    struct Outcome {
        let message: String
        let transaction: Transaction?
        let merged: Bool
    }

    static let lastTapKey = "lastTapReceived"

    /// The whole tap-handling logic, callable from tests.
    @MainActor
    static func handle(merchant: String?, amount: String?, card: String?,
                       in context: ModelContext, book: CardBook, now: Date = .now) async throws -> Outcome {
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
        UserDefaults.standard.synchronize()
        // No amount and no shop: a test run (the ▶ button in Shortcuts), not a
        // shop tap — a real tap always has an amount. Nothing is saved.
        if name.isEmpty && parsed == nil {
            let extra = cardName.isEmpty ? "" : " (it did send the card: \(cardName))"
            return Outcome(message: "Sortd is connected\(extra). Test runs don't include a purchase — pay with Apple Pay in a shop to log one.",
                           transaction: nil, merged: false)
        }
        let missingAmount = parsed == nil || parsed!.amount == 0
        let refund = AmountParser.isNegative(amount ?? "")
        let cardID = book.matchOrCreate(card)
        // A second tap with no amount at the same shop within 2 minutes is the
        // same purchase (the Deduper can't match on a missing amount).
        if missingAmount {
            let since = now.addingTimeInterval(-120)
            let shop = name.isEmpty ? "Unknown merchant" : name
            let recent = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since }))) ?? []
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
                try? context.save()
                return Outcome(message: "Refund of \(Money.format(p.amount, currency)) from \(name.isEmpty ? "the shop" : name) noted — the purchase no longer counts",
                               transaction: nil, merged: true)
            }
        }
        let purchase = IncomingPurchase(
            date: now,
            merchant: name.isEmpty ? "Unknown merchant" : name,
            amount: parsed?.amount ?? 0,
            currency: parsed?.currency ?? LocalCurrency.current(),
            card: cardID,
            source: .tap,
            note: missingAmount ? "Apple Pay sent no amount (\(seen)). Tap to fix." : (refund ? "Refund to your card" : "")
        )

        let outcome = try TransactionLogger.log(purchase, in: context)
        let t = outcome.transaction
        if refund, !t.refunded {
            t.refunded = true
            try? context.save()
            return Outcome(message: "Refund of \(Money.format(t.amount, t.currencyCode)) from \(t.merchant) noted", transaction: t, merged: false)
        }
        await FXService.backfill(in: context)

        if missingAmount {
            return Outcome(message: "Logged a purchase at \(t.merchant) — amount missing, open Sortd to fix", transaction: t, merged: false)
        }
        let money = Money.format(t.amount, t.currencyCode)
        switch outcome {
        case .added:
            return Outcome(message: "Logged \(money) at \(t.merchant) · \(t.category.name)", transaction: t, merged: false)
        case .merged:
            return Outcome(message: "\(money) at \(t.merchant) was already logged", transaction: t, merged: true)
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
