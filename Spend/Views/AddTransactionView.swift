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
    @FocusState private var amountFocused: Bool

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

    private static func symbol(_ code: String) -> String { Money.symbol(code) }

    private var parsedAmount: Decimal? {
        guard let r = AmountParser.parse(amountText), r.amount > 0 else { return nil }
        return r.amount
    }

    private var isValid: Bool {
        // Only the amount is needed; a nameless purchase is saved under its category.
        parsedAmount != nil
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
            note: note
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
        }
    }
}
