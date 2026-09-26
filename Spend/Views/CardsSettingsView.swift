import SwiftUI
import SwiftData

/// Settings → Cards: add, edit, reorder and remove the cards Spend tracks.
struct CardsSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var editing: CardInfo?
    @State private var adding = false
    private var book: CardBook { .shared }

    var body: some View {
        List {
            ListPageTitle(title: "Cards")
            if !book.active.isEmpty { Section {
                ForEach(book.active) { info in
                    Button { editing = info } label: {
                        HStack(spacing: 12) {
                            Text(CardInfo.flag(for: info.country)).font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(info.name).foregroundStyle(Color.ink)
                                    CardTypeBadge(isCredit: info.isCredit)
                                }
                                Text(detail(info)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityHint("Edit this card")
                }
                .onMove { book.move(from: $0, to: $1) }
                .onDelete { offsets in
                    for i in offsets { remove(book.active[i]) }
                }
            } footer: {
                Text("Cards are matched by their last 4 digits, or by their Wallet name for taps.")
            } }

            let archived = book.cards.filter(\.archived)
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { info in
                        HStack {
                            Text(info.name).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore") {
                                var restored = info
                                restored.archived = false
                                book.upsert(restored)
                            }
                        }
                    }
                } header: {
                    BoldHeader("Removed")
                } footer: {
                    Text("Removed cards keep their past purchases.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Cards")
        .overlay {
            if book.active.isEmpty {
                EmptyState("No cards yet", symbol: "creditcard",
                           message: "Add the cards you pay with. Apple Pay adds new ones by itself.") {
                    Button("Add Card") { adding = true }
                        .buttonStyle(.glassProminent).tint(Color.brand).foregroundStyle(Color.onBrand)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Card", systemImage: "plus") { adding = true }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { CardEditor(original: $0) }
        .sheet(isPresented: $adding) { CardEditor(original: nil) }
    }

    private func detail(_ info: CardInfo) -> String {
        var parts = [info.currency]
        if !info.allLast4.isEmpty { parts.append(info.allLast4.map { "•• \($0)" }.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func remove(_ info: CardInfo) {
        let id = info.id
        let count = (try? context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.cardRaw == id }))) ?? 0
        book.remove(info, hasPurchases: count > 0)
    }
}

/// Add or edit one card.
struct CardEditor: View {
    let original: CardInfo?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CardInfo
    @State private var digits = ""
    @State private var payDigits = ""
    @State private var words = ""

    init(original: CardInfo?) {
        self.original = original
        let currency = LocalCurrency.current()
        let start = original ?? CardInfo(name: "", shortName: "", currency: currency,
                                         country: Self.country(for: currency) ?? Locale.current.region?.identifier ?? "AU")
        _draft = State(initialValue: start)
        _digits = State(initialValue: start.last4.joined(separator: ", "))
        _payDigits = State(initialValue: (start.applePayLast4 ?? []).joined(separator: ", "))
        _words = State(initialValue: start.walletWords.joined(separator: ", "))
    }

    /// Currencies with daily rates (ECB via Frankfurter).
    static let currencies = Money.supported

    static let countries = ["AU", "SG", "MY", "NZ", "US", "GB", "IN", "ID", "JP", "HK", "CN", "KR",
                            "TH", "PH", "VN", "CA", "IE", "DE", "FR", "NL", "AE"]

    static func country(for currency: String) -> String? {
        ["AUD": "AU", "SGD": "SG", "MYR": "MY", "NZD": "NZ", "USD": "US", "GBP": "GB", "INR": "IN", "IDR": "ID",
         "JPY": "JP", "HKD": "HK", "CNY": "CN", "KRW": "KR", "THB": "TH", "PHP": "PH", "CAD": "CA", "EUR": "DE"][currency]
    }

    /// The money a card from `country` is billed in, when the app supports
    /// it: picking Hong Kong makes the card HKD, the euro countries EUR. A
    /// country whose money the app cannot hold (Vietnam, the UAE) returns
    /// nil and the currency stays as it was.
    static func currency(for country: String) -> String? {
        let code = ["AU": "AUD", "SG": "SGD", "MY": "MYR", "NZ": "NZD", "US": "USD", "GB": "GBP", "IN": "INR",
                    "ID": "IDR", "JP": "JPY", "HK": "HKD", "CN": "CNY", "KR": "KRW", "TH": "THB", "PH": "PHP",
                    "VN": "VND", "CA": "CAD", "IE": "EUR", "DE": "EUR", "FR": "EUR", "NL": "EUR", "AE": "AED"][country]
        return code.flatMap { currencies.contains($0) ? $0 : nil }
    }

    private var parsedDigits: [String] { Self.fours(digits) }
    private var parsedPayDigits: [String] { Self.fours(payDigits) }

    static func fours(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { $0.count == 4 }
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Everyday Debit", text: $draft.name)
                    TextField("Bank (optional)", text: $draft.bank)
                    Picker("Type", selection: $draft.isCredit) {
                        Text("Debit").tag(false)
                        Text("Credit").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Currency", selection: $draft.currency) {
                        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: draft.currency) { _, new in
                        if original == nil, let c = Self.country(for: new) { draft.country = c }
                    }
                    Picker("Country", selection: $draft.country) {
                        ForEach(Self.countries, id: \.self) { code in
                            Text("\(CardInfo.flag(for: code))  \(Locale.current.localizedString(forRegionCode: code) ?? code)")
                                .tag(code)
                        }
                    }
                    // A card from Hong Kong is billed in HKD: the country sets
                    // the currency, and the currency can still be changed after.
                    .onChange(of: draft.country) { _, new in
                        if let c = Self.currency(for: new), c != draft.currency { draft.currency = c }
                    }
                } footer: {
                    Text("The currency the card is billed in. Purchases abroad are still converted at that day's rate.")
                }

                Section {
                    LabeledContent("Card Number") {
                        TextField("Last 4", text: $digits)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Apple Pay Number") {
                        TextField("Last 4", text: $payDigits)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    BoldHeader("Last 4 Digits")
                } footer: {
                    Text("Bank emails show the card number. Apple Pay receipts often show a different one (Wallet › this card › ••• › Card Details). Add both.")
                }

                Section {
                    TextField("Like Everyday Visa Debit", text: $words)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    BoldHeader("Name in Apple Wallet")
                } footer: {
                    Text("Words from this card's name in Wallet, so Apple Pay taps land here. Separate with commas.")
                }
            }
            .navigationTitle(original == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                            .tint(Color.brand).disabled(!canSave).opacity(canSave ? 1 : 0.3)
                }
            }
        }
    }

    private func save() {
        var info = draft
        info.name = info.name.trimmingCharacters(in: .whitespaces)
        if info.shortName.isEmpty || original?.shortName == original?.name { info.shortName = info.name }
        info.last4 = parsedDigits
        info.applePayLast4 = parsedPayDigits.isEmpty ? nil : parsedPayDigits
        var list = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        // Always recognise the card by its own name and bank.
        for extra in [info.name.lowercased(), info.bank.lowercased()] where !extra.isEmpty && !list.contains(extra) {
            list.append(extra)
        }
        info.walletWords = list
        CardBook.shared.upsert(info)
        if original == nil { Analytics.shared.track(.cardAdded) }
        dismiss()
    }
}
