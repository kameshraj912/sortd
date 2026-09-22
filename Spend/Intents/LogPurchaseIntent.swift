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
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }

    /// What happened to one tap. `transaction` is nil for an empty test run
    /// or a run where the automation never passed a transaction at all.
    struct Outcome {
        let message: String
        let transaction: Transaction?
        let merged: Bool
        let kind: TapOutcomeKind
    }

    /// The category of what a run did, used for the Setup Guide diagnostic.
    enum TapOutcomeKind: String, Equatable {
        case saved, merged, refund, testRun, missingInput

        var label: String {
            switch self {
            case .saved: "Saved"
            case .merged: "Merged"
            case .refund: "Refund noted"
            case .testRun: "Ignored — test run"
            case .missingInput: "Transaction input missing"
            }
        }
    }

    static let lastTapKey = "lastTapReceived"
    /// What Sortd did about the last tap, in plain words — shown live in the
    /// Setup Guide next to `lastTapKey`.
    static let lastOutcomeKey = "lastTapOutcome"

    /// Writes both diagnostics and hands back the outcome, so every return
    /// path in `handle` records the same thing Settings shows. `defaults` is
    /// injectable (like `book`) so parallel tests don't race on the real
    /// UserDefaults.standard the way SetupGuideView reads.
    private static func finish(_ outcome: Outcome, now: Date, seen: String, defaults: UserDefaults) -> Outcome {
        let ts = now.formatted(date: .abbreviated, time: .standard)
        defaults.set("\(ts): \(seen)", forKey: lastTapKey)
        defaults.set("\(ts): \(outcome.kind.label) — \(outcome.message)", forKey: lastOutcomeKey)
        defaults.synchronize()
        return outcome
    }

    /// The whole tap-handling logic, callable from tests. `transactionMissing`
    /// is set by `LogWalletTapIntent` when its Transaction parameter never
    /// arrived at all (the automation isn't set to Shortcut Input) — a setup
    /// mistake, not a test run, so it gets its own diagnosis.
    @MainActor
    static func handle(merchant: String?, amount: String?, card: String?,
                       in context: ModelContext, book: CardBook, now: Date = .now,
                       transactionMissing: Bool = false, defaults: UserDefaults = .standard) async throws -> Outcome {
        // Shortcuts sometimes hands intents an empty merchant or amount
        // (developer.apple.com/forums/thread/797233). Never drop a real tap:
        // save it with amount 0 and flag it so it can be filled in.
        let parsed = AmountParser.parse(amount ?? "")
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cardName = (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep exactly what arrived, for checking the setup (Settings shows it).
        let seen = "amount “\(amount ?? "")” · merchant “\(merchant ?? "")” · card “\(card ?? "")”"

        if transactionMissing {
            return finish(Outcome(message: "Your automation isn't passing the transaction. In Shortcuts, open the automation, tap Transaction, then choose Shortcut Input.",
                                  transaction: nil, merged: false, kind: .missingInput), now: now, seen: seen, defaults: defaults)
        }
        // Nothing at all came in — no shop, no amount, no card: a test run
        // (the ▶ button in Shortcuts), not a Wallet tap. Don't save an empty
        // purchase. If ANY of the three arrived, it's a real tap: save it,
        // even with the rest missing, so nothing is silently dropped.
        if name.isEmpty && parsed == nil && cardName.isEmpty {
            return finish(Outcome(message: "Sortd is connected. Test runs don't include a purchase — pay with Apple Pay in a shop to log one.",
                                  transaction: nil, merged: false, kind: .testRun), now: now, seen: seen, defaults: defaults)
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
            if let same = recent.first(where: { $0.amount == 0 && $0.merchant == shop && $0.card == cardID }) {
                return finish(Outcome(message: "That purchase at \(shop) is already in Sortd — open it to add the amount",
                                      transaction: same, merged: true, kind: .merged), now: now, seen: seen, defaults: defaults)
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
            return finish(Outcome(message: "Refund of \(Money.format(t.amount, t.currencyCode)) from \(t.merchant) noted",
                                  transaction: t, merged: false, kind: .refund), now: now, seen: seen, defaults: defaults)
        }
        await FXService.backfill(in: context)

        if missingAmount {
            return finish(Outcome(message: "Logged a purchase at \(t.merchant) — amount missing, open Sortd to fix",
                                  transaction: t, merged: false, kind: .saved), now: now, seen: seen, defaults: defaults)
        }
        let money = Money.format(t.amount, t.currencyCode)
        switch outcome {
        case .added:
            return finish(Outcome(message: "Logged \(money) at \(t.merchant) · \(t.category.name)",
                                  transaction: t, merged: false, kind: .saved), now: now, seen: seen, defaults: defaults)
        case .merged:
            return finish(Outcome(message: "\(money) at \(t.merchant) was already logged",
                                  transaction: t, merged: true, kind: .merged), now: now, seen: seen, defaults: defaults)
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
