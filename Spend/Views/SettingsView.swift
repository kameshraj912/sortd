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
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false

    var body: some View {
        NavigationStack {
            List {
                ListPageTitle(title: "Settings")
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
                // The older Apps Script link, only for accounts already set up that way.
                if !EmailSync.accounts.isEmpty { EmailSyncSection() }

                Section {
                    NavigationLink {
                        RecurringView()
                    } label: {
                        Label("Subscriptions & Bills", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Toggle(isOn: $reminders) {
                        Label("Remind Me the Day Before", systemImage: "bell")
                    }
                    .onChange(of: reminders) { _, on in
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
                    NavigationLink {
                        CardStyleView()
                    } label: {
                        LabeledContent {
                            Text(SpendGradient.Style(rawValue: cardStyle)?.name ?? "Satin")
                        } label: {
                            Label("Card Style", systemImage: "paintpalette")
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
                } header: {
                    BoldHeader("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .brandedTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { csvFile = transactions.isEmpty ? nil : CSVExport.file(transactions) }
            .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    DataReset.deleteEverything(in: context)
                }
            } message: {
                Text("This removes every purchase, card, budget and setting from this iPhone. It can't be undone. Export first if you want a copy.")
            }
        }
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
