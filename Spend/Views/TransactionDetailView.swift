import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingCategories = false
    @State private var confirmingDelete = false
    /// The Amount field works on text and only writes back a valid amount
    /// when you leave it. Binding straight to the number saved each keystroke,
    /// so clearing "21.90" left "2" behind.
    @State private var amountText = ""
    @FocusState private var amountFocused: Bool
    /// What each field showed when the screen opened. A field is only
    /// written back when its text changed, so a name or amount that a sync
    /// updated while the screen was open is not overwritten on the way out.
    @State private var loadedAmountText = ""
    @State private var loadedMerchant = ""
    /// "Paid to" works the same way: the name goes through
    /// `MerchantName.clean` when you leave the field, so a pasted newline or
    /// a 200-character name never reaches `merchant` as typed.
    @State private var merchantText = ""
    @FocusState private var merchantFocused: Bool
    /// A category change that also moved other purchases at the shop, kept
    /// for a few seconds so Undo can put every one of them back.
    @State private var recategorised: RecategoriseChange?
    @State private var undone = 0

    /// Amounts must be under this: the same 9 whole digits the field lets
    /// you type (`AmountEntry.detailWholeDigits`). Imports have no cap, so
    /// a bigger existing amount still shows; it just can't be typed back.
    static let maxAmount: Decimal = 1_000_000_000

    /// The amount to save for what was typed, or nil to keep the old one
    /// (empty, unreadable, zero, or over the limit).
    static func committedAmount(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let parsed = AmountParser.parse(trimmed)?.amount,
              parsed > 0, parsed < maxAmount else { return nil }
        return parsed
    }

    /// Text for the field. No grouping commas: the field's own typing rule
    /// (`AmountEntry`) would refuse "1,234.00" and wipe it. No decimals for
    /// a zero-decimal currency, so ¥1200 opens as "1200", not "1200.00".
    static func amountText(_ amount: Decimal, currency: String = Money.home) -> String {
        amount == 0 ? "" : amount.formatted(.number.precision(.fractionLength(Money.decimals(currency, cents: true)))
            .grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

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
                TextField("Paid to", text: $merchantText)
                    .textInputAutocapitalization(.words)
                    .focused($merchantFocused)
                    .onSubmit(commitMerchant)
                LabeledContent("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .onSubmit(commitAmount)
                        // A key past the limit is refused on the spot, never
                        // taken and reverted later. Only typing is checked:
                        // the text set from the stored amount always shows.
                        .onChange(of: amountText) { old, new in
                            guard amountFocused else { return }
                            let kept = AmountEntry.accepted(new, replacing: old)
                            if kept != new { amountText = kept }
                        }
                        .accessibilityLabel("Amount")
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
                    LabeledContent("Original Name", value: transaction.rawMerchant)
                        .font(.footnote)
                }
            } header: {
                BoldHeader("History")
            } footer: {
                Text("If a purchase comes in twice, Sortd keeps one.")
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
        .onAppear {
            amountText = Self.amountText(transaction.amount, currency: transaction.currencyCode)
            loadedAmountText = amountText
            merchantText = transaction.merchant
            loadedMerchant = merchantText
        }
        .onChange(of: amountFocused) { _, focused in if !focused { commitAmount() } }
        .onChange(of: merchantFocused) { _, focused in if !focused { commitMerchant() } }
        .onDisappear {
            commitAmount()
            commitMerchant()
        }
        .onChange(of: transaction.amount) { _, _ in refreshAUD() }
        .onChange(of: transaction.currencyCode) { _, _ in refreshAUD() }
        .sheet(isPresented: $showingCategories) {
            CategoryPickerSheet(selected: transaction.category) { category in
                let change = try? TransactionLogger.recategorise(transaction, to: category, in: context)
                withAnimation(.snappy) { recategorised = change?.toastText == nil ? nil : change }
            }
        }
        .feedback(.undo, trigger: undone)
        .overlay(alignment: .bottom) {
            if let change = recategorised, let text = change.toastText {
                UndoToast(text: text, symbol: "tag") { undoRecategorise(change) }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: change) {
                        // The same window as a delete (`PendingDeletes`).
                        try? await Task.sleep(for: .seconds(8))
                        withAnimation(.snappy) { recategorised = nil }
                    }
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
                .font(.money)
                .contentTransition(.numericText(value: transaction.amount.double))
            BrandBar(width: 14, height: 3)
            // Chip and date on one line while they fit; otherwise stacked, so
            // neither breaks mid-word ("8:24 A / M", "Every-day"): finding 11.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    paidChip
                    when
                }
                VStack(spacing: 6) {
                    paidChip
                    when
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var paidChip: some View {
        Text(transaction.paidWithLabel)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }

    private var when: some View {
        Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
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
                                   detail: "1 \(t.currencyCode) = \(rate) \(Money.home), the rate that day", state: .done))
            }
        }
        steps.append(.init(title: "Filed under \(t.category.name)", detail: "Change it above and Sortd will remember.", state: .done))
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

    /// Saves a valid amount; otherwise keeps the old one and puts its text back.
    /// Unchanged text is left alone so it cannot undo a sync's newer amount.
    private func commitAmount() {
        if amountText != loadedAmountText, let amount = Self.committedAmount(from: amountText),
           amount != transaction.amount {
            transaction.amount = amount
        }
        if !amountFocused {
            amountText = Self.amountText(transaction.amount, currency: transaction.currencyCode)
            loadedAmountText = amountText
        }
    }

    /// Saves the tidied name. A cleared field keeps the old name, the same
    /// rule as Amount on this screen. Unchanged text is left alone so it
    /// cannot undo a name a sync merged in while the screen was open.
    private func commitMerchant() {
        if merchantText != loadedMerchant {
            let name = MerchantName.clean(merchantText)
            if !name.isEmpty, name != transaction.merchant {
                transaction.merchant = name
            }
        }
        if !merchantFocused {
            merchantText = transaction.merchant
            loadedMerchant = merchantText
        }
    }

    /// Every purchase the change moved goes back, and so does the rule.
    private func undoRecategorise(_ change: RecategoriseChange) {
        try? TransactionLogger.undo(change, in: context)
        withAnimation(.snappy) { recategorised = nil }
        undone += 1
        AccessibilityNotification.Announcement("Moved back").post()
    }

    private func refreshAUD() {
        transaction.audAmount = transaction.currencyCode == Money.home ? transaction.amount : nil
        try? context.save()
        Task { await FXService.backfill(in: context) }
    }
}
