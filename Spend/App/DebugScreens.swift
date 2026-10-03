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
            case "applepay-panel":
                // The panel on its own, no hero text above it — lets a
                // screenshot at AX5 start on the panel instead of scrolling
                // past `SetupGuideView`'s own headline first.
                ScrollView {
                    ApplePaySetupPanel(status: ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions),
                                       needsCheckCount: ApplePayStatus.needsCheckCount(in: transactions))
                        .padding()
                }
                .background(Color.page)
            case "wallet-guide":
                // One page of the picture guide, drawn on its own: the panel
                // now keeps the guide behind a collapsed disclosure, and the
                // pager's own scroll position doesn't jump on a cold launch,
                // so there's no other one-tap way to land on a given page
                // for a screenshot. SPEND_GUIDE_PAGE picks the page;
                // SPEND_GUIDE_ROUTE=byhand switches route (see
                // `WalletSetupGuide`).
                let route: WalletSetupGuide.Route = ProcessInfo.processInfo.environment["SPEND_GUIDE_ROUTE"] == "byhand" ? .byHand : .quick
                let pageIndex = Int(ProcessInfo.processInfo.environment["SPEND_GUIDE_PAGE"] ?? "") ?? 0
                let pages = route == .quick ? WalletSetupGuide.quickPages : WalletSetupGuide.byHandPages
                if let p = pages.first(where: { $0.id == pageIndex }) {
                    Color.page.overlay {
                        VStack(alignment: .leading, spacing: 12) {
                            ShortcutsMock(step: p.id, route: route).frame(height: 260)
                            Text(p.title).font(.headline)
                            Text(p.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
            case "tip": Color.page.sheet(isPresented: .constant(true)) { TipJarView() }
            case "scan": Color.page.sheet(isPresented: .constant(true)) { ReceiptScanView { _ in } }
            case "privacy": PrivacyView()
            case "privacy-security": PrivacySecuritySettingsView()
            case "backup": BackupDataSettingsView()
            case "purchase-sources": PurchaseSourcesSettingsView()
            case "learned": LearnedRulesView()
            case "developer": DeveloperMenuView()
            case "help": HelpFeedbackSettingsView()
            case "about": AboutSettingsView()
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
        // Only start on a tab this nav option actually shows.
        case "search" where NavOption.current.hasSearchTab: .search
        case "you" where NavOption.current.hasYouTab: .you
        default: .home
        }
    }
}
#endif
