import SwiftUI
import SwiftData

/// The top-level Settings screen: a short list of grouped rows that each
/// push to their own sub-page (in `Views/Settings/`), the
/// same shape as iOS's own Settings app — but styled like the rest of
/// Sortd: plain monochrome SF Symbols, no coloured tiles.
struct SettingsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \MerchantRule.updatedAt, order: .reverse) private var rules: [MerchantRule]
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    #if SORTD_SIGNIN
    @State private var account = AccountStore.shared
    #endif

    var body: some View {
        NavigationStack(path: Bindable(Router.shared).settingsPath) {
            List {
                ListPageTitle(title: "Settings")

                Section {
                    #if SORTD_SIGNIN
                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Account", subtitle: accountSubtitle, symbol: "person.crop.circle")
                    }
                    #endif
                    NavigationLink {
                        PurchaseSourcesSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Purchase Sources", subtitle: sourcesSubtitle, symbol: "wave.3.right")
                    }
                    NavigationLink {
                        BillsRemindersSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Bills & Reminders", subtitle: reminders ? "Reminders on" : nil, symbol: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink {
                        CardsAppearanceSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Cards & Appearance", subtitle: cardsSubtitle, symbol: "creditcard")
                    }
                    NavigationLink {
                        CurrencySettingsView()
                    } label: {
                        SettingsRowLabel(title: "Currency", subtitle: home, symbol: "dollarsign.circle")
                    }
                    NavigationLink {
                        LearnedRulesView()
                    } label: {
                        SettingsRowLabel(title: "Learned Categories", subtitle: categoriesSubtitle, symbol: "brain")
                    }
                    NavigationLink {
                        PrivacySecuritySettingsView()
                    } label: {
                        SettingsRowLabel(title: "Privacy & Security", subtitle: lockEnabled ? "\(AppLock.methodName) on" : "App Lock off", symbol: "lock.shield")
                    }
                    NavigationLink {
                        BackupDataSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Backup & Data", symbol: "externaldrive")
                    }
                    NavigationLink {
                        HelpFeedbackSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Help & Feedback", symbol: "questionmark.circle")
                    }
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        SettingsRowLabel(title: "About", subtitle: aboutSubtitle, symbol: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .brandedTitle("Settings")
            .navigationDestination(for: Router.Destination.self) { destination in
                switch destination {
                case .importing: ImportView()
                case .recurring: RecurringView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { Router.shared.showingSettings = false }
                        .fontWeight(.semibold)
                        .tint(Color.ink)
                }
            }
            .onAppear { Exports.clear() }
        }
    }

    #if SORTD_SIGNIN
    private var accountSubtitle: String {
        account.current.map { "Signed in with \($0.provider.name)" } ?? "Not signed in"
    }
    #endif

    private var sourcesSubtitle: String {
        switch ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: transactions) {
        case .tapLogged(let date, _, _, _): "Last tap \(date.formatted(.relative(presentation: .named)))"
        case .tapNeedsCheck: "Last tap needs a check"
        case .shortcutReached: "Connected · waiting for a shop tap"
        case .notConnected: "Not set up yet"
        }
    }

    private var cardsSubtitle: String {
        let count = Card.mine.count
        return "\(count) card\(count == 1 ? "" : "s")"
    }

    private var categoriesSubtitle: String {
        "\(rules.count) learned"
    }

    private var aboutSubtitle: String {
        "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")"
    }
}
