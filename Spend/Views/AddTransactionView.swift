import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastCard") private var lastCard: Card = .other

    @State private var amountText = ""
    @State private var currency = LocalCurrency.current()
    @State private var merchant = ""
    @State private var category: SpendCategory = .other
    @State private var categoryTouched = false
    @State private var card: Card = .nab
    @State private var date = Date.now
    @State private var note = ""
    @State private var saved = 0
    @State private var showingCategories = false
    @State private var showingScanner = false
    /// True once fields were filled from a scanned receipt.
    @State private var scanned = false
    @FocusState private var amountFocused: Bool
    @State private var saveError: String?

    /// Home and local currency first, then the rest.
    private static var currencies: [String] {
        let first = [Money.home, LocalCurrency.current()]
        return Array(NSOrderedSet(array: first + Money.supported)) as! [String]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    amountField
                    scanButton
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Merchant", text: $merchant)
                        .textInputAutocapitalization(.words)
                        .onChange(of: merchant) { _, name in
                            // Suggest a category while typing until Raj picks one himself.
                            guard !categoryTouched else { return }
                            let learned = (try? TransactionLogger.learnedRules(in: context)) ?? [:]
                            withAnimation(.snappy) {
                                category = Categorizer.category(for: name, learned: learned)
                            }
                        }
                    Button { showingCategories = true } label: {
                        HStack(spacing: 10) {
                            Text("Category").foregroundStyle(.primary)
                            Spacer()
                            if !categoryTouched && category != .other {
                                Text("Suggested")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            CategoryIcon(category: category, size: 26)
                            Text(category.name).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Category, \(category.name)")
                }

                Section(bold: "Paid With") {
                    Picker("Card", selection: $card) {
                        ForEach(Card.mine + [.other]) { Text($0.name).tag($0) }
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }

                Section(bold: "Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("New Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", action: save)
                        .tint(Color.brand)
                        .disabled(!isValid)
                        .opacity(isValid ? 1 : 0.3)
                }
            }
            .sheet(isPresented: $showingScanner) {
                if ProStore.shared.isPro { ReceiptScanView(onRead: apply) } else { PaywallView(feature: .camera) }
            }
            .sheet(isPresented: $showingCategories) {
                CategoryPickerSheet(selected: category) { picked in
                    category = picked
                    categoryTouched = true
                }
            }
            .onAppear {
                card = Card.mine.contains(lastCard) ? lastCard : (Card.mine.first ?? .other)
                amountFocused = true
            }
            .sensoryFeedback(.success, trigger: saved)
            .alert("Not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
        }
    }

    /// Big centred amount like Cash App, with a small currency switch below.
    private var amountField: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Self.symbol(currency))
                    .font(.title.weight(.bold))
                    .foregroundStyle(amountText.isEmpty ? .tertiary : .secondary)
                TextField("0", text: $amountText)
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .fixedSize()
                    .accessibilityLabel("Amount in \(currency)")
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { amountFocused = true }

            Menu {
                Picker("Currency", selection: $currency) {
                    ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currency)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: .capsule)
            }
            .tint(.secondary)
            .accessibilityLabel("Currency, \(currency)")
        }
        .padding(.vertical, 16)
    }

    /// "Scan Receipt", or after a scan, a note to check what was filled in.
    private var scanButton: some View {
        VStack(spacing: 10) {
            Button { showingScanner = true } label: {
                Label(scanned ? "Scan Again" : "Scan Receipt", systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .surface(radius: 20)
            }
            .buttonStyle(.plain)

            if scanned {
                Label("Filled from your receipt — check it", systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Fills in what the scan found. Never saves: Raj checks and taps the tick.
    private func apply(_ r: ReceiptReading) {
        if let amount = r.amount { amountText = amount }
        if let code = r.currency, Self.currencies.contains(code) { currency = code }
        if let name = r.merchant { merchant = name }   // suggests a category via onChange
        if let when = r.date { date = min(when, .now) }
        if let found = CardBook.shared.card(last4: r.last4), Card.mine.contains(found) { card = found }
        amountFocused = false
        scanned = true
    }

    private static func symbol(_ code: String) -> String { Money.symbol(code) }

    private var parsedAmount: Decimal? {
        guard let r = AmountParser.parse(amountText), r.amount > 0 else { return nil }
        return r.amount
    }

    private var isValid: Bool {
        // Only the amount is needed; a nameless purchase is saved under its category.
        parsedAmount != nil
    }

    /// Scanned purchases say so in their note.
    private var noteToSave: String {
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scanned, !typed.localizedCaseInsensitiveContains("Scanned receipt") else { return note }
        return typed.isEmpty ? "Scanned receipt" : typed + " · Scanned receipt"
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let purchase = IncomingPurchase(
            date: date,
            merchant: merchant.trimmingCharacters(in: .whitespaces).isEmpty
                ? category.name : merchant.trimmingCharacters(in: .whitespaces),
            amount: amount,
            currency: currency,
            card: card,
            source: .manual,
            category: category,
            note: noteToSave
        )
        do {
            let outcome = try TransactionLogger.log(purchase, in: context)
            if categoryTouched {
                try TransactionLogger.recategorise(outcome.transaction, to: category, in: context)
            }
            lastCard = card
            saved += 1
            Task { await FXService.backfill(in: context) }
            dismiss()
        } catch {
            log.error("Manual add failed: \(error.localizedDescription)")
            saveError = "Couldn't save this purchase. Please try again."
        }
    }
}
