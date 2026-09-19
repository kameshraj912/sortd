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
        // Shortcuts sometimes hands intents an empty merchant or amount
        // (developer.apple.com/forums/thread/797233). Never drop the tap:
        // save it with amount 0 and flag it so Raj can fill it in.
        let parsed = AmountParser.parse(amount ?? "")
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing at all came in: this is a test run (the ▶ button in
        // Shortcuts), not a Wallet tap. Don't save an empty purchase.
        let cardName = (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty && parsed == nil && cardName.isEmpty {
            return .result(dialog: "Sortd is connected. Test runs don't include a purchase — pay with Apple Pay in a shop to log one.")
        }
        let missingAmount = parsed == nil || parsed!.amount == 0
        let purchase = IncomingPurchase(
            date: .now,
            merchant: name.isEmpty ? "Unknown merchant" : name,
            amount: parsed?.amount ?? 0,
            currency: parsed?.currency ?? LocalCurrency.current(),
            card: CardBook.shared.matchOrCreate(card),
            source: .tap,
            note: missingAmount ? "Apple Pay sent no amount (got “\(amount ?? "nothing")”). Tap to fix." : ""
        )

        let context = SpendStore.container.mainContext
        let outcome = try TransactionLogger.log(purchase, in: context)
        let t = outcome.transaction
        await FXService.backfill(in: context)

        if missingAmount {
            return .result(dialog: "Logged a purchase at \(t.merchant) — amount missing, open Sortd to fix")
        }
        let money = Money.format(t.amount, t.currencyCode)
        switch outcome {
        case .added:
            return .result(dialog: "Logged \(money) at \(t.merchant) · \(t.category.name)")
        case .merged:
            return .result(dialog: "\(money) at \(t.merchant) was already logged")
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
