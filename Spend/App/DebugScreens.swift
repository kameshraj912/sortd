#if DEBUG
import SwiftUI
import SwiftData

/// Opens one screen directly, for screenshots and UI checks in the
/// simulator. Launch with SPEND_SCREEN=<name>, or SPEND_TAB=<tab> for a tab.
/// Not compiled into release builds.
struct DebugScreenHost: View {
    let name: String
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var budget: Double = UserDefaults.standard.double(forKey: "monthlyBudget")

    var body: some View {
        NavigationStack {
            switch name {
            case "recurring": RecurringView()
            case "cards": CardsSettingsView()
            case "styles": CardStyleView()
            case "homev2": HomeMockup()
            case "card-editor": Color.page.sheet(isPresented: .constant(true)) { CardEditor(original: nil) }
            case "add": Color.page.sheet(isPresented: .constant(true)) { AddTransactionView() }
            case "budget": Color.page.sheet(isPresented: .constant(true)) { BudgetSheet(budget: $budget) }
            case "setup": SetupGuideView()
            case "paywall": Color.page.sheet(isPresented: .constant(true)) { PaywallView() }
            case "gmail-connect": Color.page.sheet(isPresented: .constant(true)) { ConnectGmailSheet() }
            case "scan": Color.page.sheet(isPresented: .constant(true)) { ReceiptScanView { _ in } }
            case "privacy": PrivacyView()
            case "settings-sources": PurchaseSourcesSettingsView()
            case "settings-bills": BillsRemindersSettingsView()
            case "settings-cards": CardsAppearanceSettingsView()
            case "settings-currency": CurrencySettingsView()
            case "settings-categories": LearnedRulesView()
            case "settings-privacy": PrivacySecuritySettingsView()
            case "settings-backup": BackupDataSettingsView()
            case "settings-help": HelpFeedbackSettingsView()
            case "settings-about": AboutSettingsView()
            case "import": Color.page.sheet(isPresented: .constant(true)) { ImportView() }
            case "widgets": WidgetsGuideView()
            case "card": CardDetailView(card: Card.mine.first ?? .other)
            case "category": CategoryDetailView(category: .housing)
            case "txn":
                if let t = transactions.first(where: { $0.platform == "doordash" }) ?? transactions.first {
                    TransactionDetailView(transaction: t)
                }
            default: Text("Unknown screen \(name)")
            }
        }
    }
}

extension AppTab {
    /// SPEND_TAB=activity etc.
    static var debugStart: AppTab {
        switch ProcessInfo.processInfo.environment["SPEND_TAB"] {
        case "activity": .activity
        case "insights": .insights
        case "settings": .settings
        default: .home
        }
    }
}
#endif
