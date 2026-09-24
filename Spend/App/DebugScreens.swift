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

/// Opens one paywall screen: SPEND_PAYWALL_STEP=features | trial | plans |
/// single | onboarding | feature-<gmail|camera|insights|recurring|budgets>,
/// or features-<gmail|camera|insights|bills> for one "What you get" page.
/// Add SPEND_PRO=0 so a comped or demo Pro doesn't close it.
struct PaywallDebugHost: View {
    let value: String

    var body: some View {
        if value == "onboarding" {
            // As it appears at the end of setup: full screen, "Not Now".
            PaywallFlow(closeTitle: "Not Now", onBack: {}, onClose: {})
        } else {
            Color.page.ignoresSafeArea().sheet(isPresented: .constant(true)) { sheet }
        }
    }

    @ViewBuilder private var sheet: some View {
        if value == "single" {
            PaywallView()
        } else if value.hasPrefix("feature-") {
            FeaturePaywallSheet(feature: ProStore.Feature(rawValue: String(value.dropFirst(8))) ?? .camera)
        } else if value.hasPrefix("features-") {
            PaywallFlow(startPage: PaywallPage(rawValue: String(value.dropFirst(9))), onClose: {})
        } else {
            PaywallFlow(start: PaywallStep(rawValue: value) ?? .features, onClose: {})
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
