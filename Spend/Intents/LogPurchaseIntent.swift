import AppIntents
import SwiftData

/// Called by the Shortcuts "Transaction" automation every time Raj taps a
/// card in Wallet. Runs in the background; the app does not open.
struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase"
    static let description = IntentDescription(
        "Adds a purchase to Sortd. Pair it with the Wallet “Transaction” automation so every Apple Pay tap is logged.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Merchant", description: "Shop name. In the automation, pick the Merchant variable.")
    var merchant: String?

    @Parameter(title: "Amount", description: "In the automation, pick the Amount variable. Text like “A$4.50” is fine.")
    var amount: String?

    @Parameter(title: "Card", description: "In the automation, pick the Card or Pass variable.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Shortcuts sometimes hands intents an empty merchant or amount
        // (developer.apple.com/forums/thread/797233). Never drop the tap:
        // save it with amount 0 and flag it so Raj can fill it in.
        let parsed = AmountParser.parse(amount ?? "")
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
    }
}
