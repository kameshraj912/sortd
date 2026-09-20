import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \MerchantRule.updatedAt, order: .reverse) private var rules: [MerchantRule]
    @State private var refreshing = false
    @AppStorage("cardStyle") private var cardStyle = SpendGradient.Style.satin.rawValue
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmingDelete = false
    @State private var csvFile: URL?
    @State private var backupFile: URL?
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var showingPaywall = false
    @State private var pro = ProStore.shared
    @State private var knock = SecretKnock.shared

    var body: some View {
        NavigationStack(path: Bindable(Router.shared).settingsPath) {
            List {
                ListPageTitle(title: "Settings")
                Section {
                    Button { showingPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image("BrandIcon").resizable().frame(width: 30, height: 30)
                                .clipShape(.rect(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sortd Pro").foregroundStyle(Color.ink)
                                Text(pro.isPro ? "Active. Thank you." : "Gmail, receipt camera, insights and more")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: pro.isPro ? "checkmark.seal.fill" : "chevron.right")
                                .foregroundStyle(pro.isPro ? Color.up : Color.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink {
                        SetupGuideView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Pay Auto-Logging")
                                Text(lastTapText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wave.3.right")
                        }
                    }
                } header: {
                    BoldHeader("Sources")
                } footer: {
                    Text("Logs in-store Apple Pay taps the moment you pay.")
                }

                GmailSection()

                Section {
                    NavigationLink {
                        ProGate(feature: .recurring) { RecurringView() }
                    } label: {
                        Label("Subscriptions & Bills", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Toggle(isOn: $reminders) {
                        Label("Remind Me the Day Before", systemImage: "bell")
                    }
                    .onChange(of: reminders) { _, on in
                        if on, !ProStore.shared.isPro { reminders = false; showingPaywall = true; return }
                        Task {
                            if on, !(await Reminders.requestPermission()) { reminders = false }
                            let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
                            await Reminders.reschedule(all.recurring())
                        }
                    }
                } header: {
                    BoldHeader("Recurring")
                } footer: {
                    Text("A notification at 9 am the day before a subscription or bill is due.")
                }

                Section {
                    NavigationLink {
                        CardsSettingsView()
                    } label: {
                        LabeledContent {
                            Text("\(Card.mine.count)")
                        } label: {
                            Label("Cards", systemImage: "creditcard")
                        }
                    }
                    Picker(selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .onChange(of: appearance) { _, value in Appearance.apply(value) }
                    NavigationLink {
                        CardStyleView()
                    } label: {
                        LabeledContent {
                            Text(SpendGradient.Style(rawValue: cardStyle)?.name ?? "Satin")
                        } label: {
                            Label("Card Style", systemImage: "paintpalette")
                        }
                    }
                    NavigationLink {
                        WidgetsGuideView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Widgets")
                                Text("Home and Lock Screen · light or dark")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                } header: {
                    BoldHeader("Cards")
                } footer: {
                    Text("Cards are coloured by what you spend on them. Appearance follows your iPhone unless you pick Light or Dark.")
                }

                Section {
                    Picker("Totals shown in", selection: $home) {
                        ForEach(Money.supported, id: \.self) { code in
                            Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                        }
                    }
                    .onChange(of: home) { _, new in
                        Task {
                            refreshing = true
                            await FXService.rebase(to: new, in: context)
                            refreshing = false
                        }
                    }
                    LabeledContent("Purchase currency", value: "\(LocalCurrency.current()) (from your time zone)")
                    Button {
                        Task {
                            refreshing = true
                            await FXService.backfill(in: context)
                            refreshing = false
                        }
                    } label: {
                        HStack {
                            Text("Update Exchange Rates")
                            Spacer()
                            if refreshing { ProgressView() }
                        }
                    }
                    .disabled(refreshing)
                } header: {
                    BoldHeader("Currency")
                } footer: {
                    Text("Purchases in other currencies are converted to \(home) at that day's European Central Bank rate.")
                }

                Section(bold: "Learning") {
                    NavigationLink {
                        LearnedRulesView()
                    } label: {
                        LabeledContent("Learned Categories", value: "\(rules.count)")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { lockEnabled },
                        set: { on in
                            guard on else { lockEnabled = false; return }
                            // Check it works before turning it on.
                            Task {
                                if await AppLock.authenticate(reason: "Turn on the lock for Sortd.") {
                                    lockEnabled = true
                                }
                            }
                        }
                    )) {
                        Label("Require \(AppLock.methodName)", systemImage: AppLock.methodSymbol)
                    }
                } header: {
                    BoldHeader("Security")
                } footer: {
                    Text("Sortd locks when you open it, and when you come back after more than a minute.")
                }

                Section {
                    if let file = backupFile {
                        ShareLink(item: file) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Save a Backup")
                                    Text(lastBackupText)
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "arrow.down.document")
                            }
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            UserDefaults.standard.set(Date.now, forKey: Self.lastBackupKey)
                        })
                    }
                    NavigationLink {
                        ImportView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import")
                                Text("A statement, a screenshot, or a backup")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                } header: {
                    BoldHeader("Backup")
                } footer: {
                    Text("Sortd keeps everything on this iPhone, so a backup is the only way to move to a new phone or get your purchases back if this one is lost. Save it to Files or iCloud Drive — it never goes through a Sortd server, because there isn't one.")
                }

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    if let file = csvFile {
                        ShareLink(item: file) {
                            Label("Export Purchases (CSV)", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                    .foregroundStyle(Color.down)
                } header: {
                    BoldHeader("Your Data")
                } footer: {
                    Text("Export gives you every purchase as a spreadsheet file. Delete removes everything Sortd has stored on this iPhone.")
                }

                Section {
                    LabeledContent("Purchases", value: "\(transactions.count)")
                    LabeledContent("Stored", value: "On this iPhone only")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .contentShape(.rect)
                        .onTapGesture { knock.knock() }
                        .accessibilityHint("Tapped five times, opens a code screen")
                    // The flat tab bar sits over the last row otherwise, and
                    // the last row is the one with the hidden door in it.
                    Color.clear
                        .frame(height: 1)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                } header: {
                    BoldHeader("About")
                } footer: {
                    if let hint = knock.hint {
                        Text(hint).foregroundStyle(.secondary)
                    } else if let source = CompedPro.source() {
                        // Named so a tester can say which code they used —
                        // the app has no server and reports nothing.
                        Text("Pro is on the house. Code: \(source)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .brandedTitle("Settings")
            .navigationDestination(for: Router.Destination.self) { destination in
                switch destination {
                case .importing: ImportView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { refreshFiles() }
            .onChange(of: transactions.count) { _, _ in refreshFiles() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $knock.isOpen) { SecretCodeSheet() }
            .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    DataReset.deleteEverything(in: context)
                }
            } message: {
                Text("This removes every purchase, card, budget and setting from this iPhone. It can't be undone. Export first if you want a copy.")
            }
        }
    }

    static let lastBackupKey = "lastBackupSaved"

    /// The share sheet needs a real file, so both are written when the
    /// screen opens and whenever the number of purchases changes.
    private func refreshFiles() {
        csvFile = transactions.isEmpty ? nil : CSVExport.file(transactions)
        backupFile = try? Backup.file(in: context)
    }

    private var lastBackupText: String {
        guard let last = UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date else {
            return "You haven't saved one yet"
        }
        return "Last saved \(last.formatted(.relative(presentation: .named)))"
    }

    private var lastTapText: String {
        guard let last = transactions.first(where: { $0.seenIn.contains(.tap) }) else {
            return "Not set up yet"
        }
        return "Last tap logged \(last.date.formatted(.relative(presentation: .named)))"
    }
}

struct LearnedRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MerchantRule.key) private var rules: [MerchantRule]

    var body: some View {
        List {
            ListPageTitle(title: "Learned Categories", subtitle: "Categories you've set for a merchant are used next time.")
            if rules.isEmpty {
                ContentUnavailableView(
                    "Nothing Learned Yet",
                    systemImage: "brain",
                    description: Text("Change a purchase’s category and Sortd will remember it for that merchant.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(rules) { rule in
                HStack(spacing: 12) {
                    CategoryIcon(category: rule.category, size: 30)
                    Text(rule.key)
                    Spacer()
                    Text(rule.category.name).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(rules[i]) }
                try? context.save()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Learned Categories")
    }
}
