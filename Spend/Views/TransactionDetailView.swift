import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingCategories = false
    @State private var confirmingDelete = false

    private static var currencies: [String] {
        Array(NSOrderedSet(array: [Money.home, LocalCurrency.current()] + Money.supported)) as! [String]
    }

    var body: some View {
        Form {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            Section(bold: "Details") {
                TextField("Merchant", text: $transaction.merchant)
                    .textInputAutocapitalization(.words)
                LabeledContent("Amount") {
                    TextField("0.00", value: $transaction.amount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                Picker("Currency", selection: $transaction.currencyCode) {
                    ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                }
                if transaction.currencyCode != Money.home {
                    LabeledContent("In \(Money.home)") {
                        Text(transaction.needsRate ? "Waiting for rate" : Money.format(transaction.audValue, Money.home))
                            .monospacedDigit()
                    }
                }
                Button { showingCategories = true } label: {
                    LabeledContent("Category") {
                        HStack(spacing: 8) {
                            CategoryIcon(category: transaction.category, size: 24)
                            Text(transaction.category.name)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Picker("Card", selection: $transaction.cardRaw) {
                    ForEach(Card.mine + [.other]) { Text($0.name).tag($0.rawValue) }
                }
                DatePicker("Date", selection: $transaction.date)
            }

            Section(bold: "Note") {
                TextField("Add a note", text: $transaction.note, axis: .vertical)
                    .lineLimit(1...5)
            }

            Section {
                Timeline(steps: timelineSteps)
                    .padding(.vertical, 4)
                if transaction.rawMerchant != transaction.merchant {
                    LabeledContent("Original name", value: transaction.rawMerchant)
                        .font(.footnote)
                }
            } header: {
                BoldHeader("Updates")
            } footer: {
                Text("When two sources report the same purchase, Sortd keeps one copy.")
            }

            Section {
                Button("Delete Purchase", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
                .tint(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .navigationTitle(transaction.merchant.isEmpty ? "Purchase" : transaction.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: transaction.amount) { _, _ in refreshAUD() }
        .onChange(of: transaction.currencyCode) { _, _ in refreshAUD() }
        .sheet(isPresented: $showingCategories) {
            CategoryPickerSheet(selected: transaction.category) { category in
                try? TransactionLogger.recategorise(transaction, to: category, in: context)
            }
        }
        .confirmationDialog("Delete this purchase?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(transaction)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("\(Money.format(transaction.amount, transaction.currencyCode)) at \(transaction.merchant)")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CategoryIcon(category: transaction.category, size: 64)
            Text(Money.format(transaction.amount, transaction.currencyCode))
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            BrandBar(width: 14, height: 3)
            HStack(spacing: 6) {
                Text(transaction.paidWithLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// What happened to this purchase, oldest first, like Wise's transfer updates.
    private var timelineSteps: [Timeline.Step] {
        let t = transaction
        var steps = [Timeline.Step(
            title: "Paid at \(t.merchant)",
            detail: "\(t.card == .other ? t.paidWithLabel : t.card.name) · \(t.date.formatted(date: .abbreviated, time: .shortened))",
            state: .done)]
        for source in t.seenIn {
            steps.append(.init(title: source.label, detail: sourceDetail(source), state: .done))
        }
        if t.needsReview {
            steps.append(.init(title: "Amount missing", detail: "Apple Pay didn’t send one. Type it in above.", state: .current))
        } else if t.currencyCode != Money.home {
            if t.needsRate {
                steps.append(.init(title: "Converting to \(Money.home)", detail: "Waiting for that day’s exchange rate", state: .current))
            } else if !t.refunded, t.amount > 0, let converted = t.audAmount {
                let rate = (converted / t.amount).rounded(4)
                steps.append(.init(title: "Converted to \(Money.format(t.audValue, Money.home))",
                                   detail: "1 \(t.currencyCode) = \(rate) \(Money.home) (ECB rate)", state: .done))
            }
        }
        steps.append(.init(title: "Filed under \(t.category.name)", detail: "Change it above; Sortd learns for next time", state: .done))
        return steps
    }

    private func sourceDetail(_ source: TxnSource) -> String {
        switch source {
        case .tap: "Logged the moment you paid"
        case .email: "Matched from your email receipt"
        case .csv: "Matched from your statement"
        case .bank: "Confirmed by your bank feed"
        case .manual: "You added this yourself"
        }
    }

    private func refreshAUD() {
        transaction.audAmount = transaction.currencyCode == Money.home ? transaction.amount : nil
        try? context.save()
        Task { await FXService.backfill(in: context) }
    }
}
