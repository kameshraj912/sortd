import SwiftUI
import SwiftData

/// The top-level Settings screen: a Pro row, then a short list of grouped
/// rows that each push to their own sub-page (in `Views/Settings/`), the
/// same shape as iOS's own Settings app — but styled like the rest of
/// Sortd: plain monochrome SF Symbols, no coloured tiles.
struct SettingsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \MerchantRule.updatedAt, order: .reverse) private var rules: [MerchantRule]
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var showingPaywall = false
    @State private var pro = ProStore.shared
    /// The app icon on the Pro row, the same column as the row symbols.
    @ScaledMetric(relativeTo: .subheadline) private var proIcon: CGFloat = 24

    var body: some View {
        NavigationStack(path: Bindable(Router.shared).settingsPath) {
            SettingsList {
                ListPageTitle(title: "Settings")

                Section {
                    Button { showingPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image("BrandIcon").resizable().frame(width: proIcon, height: proIcon)
                                .clipShape(.rect(cornerRadius: proIcon * 0.23, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sortd Pro").font(.subheadline).foregroundStyle(Color.ink)
                                Text(pro.isBetaFree ? "Free during the beta" : pro.isPro ? "Active. Thank you." : Features.gmail ? "Gmail, receipt camera, insights and more" : "Receipt camera, insights and more")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: pro.isPro ? "checkmark.seal.fill" : "chevron.right")
                                .foregroundStyle(pro.isPro ? Color.up : Color.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(pro.isPro ? "" : "Opens Sortd Pro")
                }

                Section {
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
                        SettingsRowLabel(title: "Categories", subtitle: categoriesSubtitle, symbol: "brain")
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
                case .recurring: ProGate(feature: .recurring) { RecurringView() }
                }
            }
            .hidesNavigationBar()
            .onAppear { Exports.clear() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var sourcesSubtitle: String {
        guard let last = transactions.first(where: { $0.seenIn.contains(.tap) }) else {
            return "Not set up yet"
        }
        // Relative, like Purchase Sources: a time alone reads as today.
        return "Last tap \(last.date.formatted(.relative(presentation: .named)))"
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
