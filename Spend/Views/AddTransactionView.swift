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
    @State private var quick = ""
    @FocusState private var quickFocused: Bool
    /// True while Apple Intelligence reads the quick line.
    @State private var reading = false
    /// Apple Intelligence's category, used when the merchant rules have none.
    @State private var aiCategory: SpendCategory?
    /// The merchant name `aiCategory` was read for. Once the name is edited
    /// by hand the guess no longer applies.
    @State private var aiCategoryMerchant = ""
    /// Shown under the quick line when nothing could be read from it.
    @State private var quickProblem: String?
    @State private var confirmingDiscard = false
    /// Keystrokes the amount field refused (too long, a third decimal).
    @State private var refusedKeys = 0

    /// Home and local currency first, then the rest.
    private static var currencies: [String] {
        let first = [Money.home, LocalCurrency.current()]
        return Array(NSOrderedSet(array: first + Money.supported)) as! [String]
    }

    /// One line instead of four fields. Whatever it works out goes into the
    /// fields below for checking rather than straight into the store — a
    /// wrong guess should cost a glance, not a wrong total.
    private var quickField: some View {
        HStack(spacing: 10) {
            Image(systemName: QuickEntryAI.isAvailable ? "sparkles" : "text.cursor")
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: reading)
                .accessibilityHidden(true)
            TextField("Coffee 5.50 yesterday", text: $quick)
                .focused($quickFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .onSubmit(applyQuick)
                .onChange(of: quick) { quickProblem = nil }
            if reading {
                ProgressView()
            } else if !quick.isEmpty {
                Button("Fill", action: applyQuick)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ink)
            }
        }
        .accessibilityLabel("Quick entry")
        .accessibilityHint("Type a name and an amount, like coffee 5.50")
    }

    private func applyQuick() {
        let line = quick
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty, !reading else { return }
        quickFocused = false
        Task {
            if QuickEntryAI.isAvailable {
                reading = true
                let ai = await QuickEntryAI.read(line)
                reading = false
                if let ai {
                    fill(merchant: ai.merchant, amount: ai.amount, currency: ai.currency,
                         daysAgo: ai.daysAgo, category: ai.category)
                    quick = ""
                    return
                }
            }
            // No Apple Intelligence (or it couldn't read it): the plain reader.
            guard let plain = QuickEntry.read(line) else {
                withAnimation(.snappy) { quickProblem = "Couldn't read that. Try \u{2018}coffee 5.50\u{2019}." }
                quickFocused = true
                return
            }
            fill(merchant: plain.merchant, amount: plain.amount, currency: plain.currency,
                 daysAgo: plain.daysAgo, category: nil)
            quick = ""
        }
    }

    private func fill(merchant name: String, amount: Decimal?, currency code: String?,
                      daysAgo: Int, category guess: SpendCategory?) {
        withAnimation(.snappy) {
            if !name.isEmpty { merchant = name }
            // "5.50", not "5.5"; formatted from the Decimal so a huge number
            // can't crash it.
            if let amount { amountText = QuickEntry.fieldText(amount) }
            if let code { currency = code }
            if daysAgo > 0 {
                date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? date
            }
            // The model's category, only where the merchant rules have none,
            // and only for the name it read (see the merchant field).
            aiCategory = guess
            aiCategoryMerchant = name.isEmpty ? merchant : name
            if let guess, !categoryTouched, category == .other { category = guess }
        }
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
                    quickField
                } footer: {
                    if let quickProblem {
                        Label(quickProblem, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Text(QuickEntryAI.isAvailable
                             ? "Type it how you'd say it. Apple Intelligence fills in the rest on this iPhone."
                             : "Type it how you'd say it, then tap Fill.")
                    }
                }

                Section {
                    TextField("Paid to", text: $merchant)
                        .textInputAutocapitalization(.words)
                        .onChange(of: merchant) { _, name in
                            // A retyped name drops the model's guess for the old one.
                            // fill() records the name it set, so its own change keeps it.
                            if name != aiCategoryMerchant { aiCategory = nil }
                            // Suggest a category while typing until Raj picks one himself.
                            guard !categoryTouched else { return }
                            let learned = (try? TransactionLogger.learnedRules(in: context)) ?? [:]
                            withAnimation(.snappy) {
                                let rule = Categorizer.category(for: name, learned: learned)
                                category = rule == .other ? aiCategory ?? .other : rule
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
            // Dragging the form puts the number pad away, so the rest of the
            // sheet can be reached at any text size.
            .scrollDismissesKeyboard(.interactively)
            .background(Color.page)
            .navigationTitle("New Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if hasInput { confirmingDiscard = true } else { dismiss() }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", action: save)
                        .tint(Color.brand)
                        .disabled(!isValid)
                        .opacity(isValid ? 1 : 0.3)
                }
                // The number pad has no Return key, so without this there was
                // no way to put it away and reach the rest of the form.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; quickFocused = false }
                        .fontWeight(.semibold)
                }
            }
            // A half-typed purchase is real work; swiping the sheet away used
            // to bin it without a word.
            .interactiveDismissDisabled(hasInput)
            .confirmationDialog("Discard this purchase?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(isPresented: $showingScanner) { ReceiptScanView(onRead: apply) }
            .sheet(isPresented: $showingCategories) {
                CategoryPickerSheet(selected: category, footer: CategoryPickerSheet.moveAllFooter) { picked in
                    category = picked
                    categoryTouched = true
                }
            }
            .onAppear {
                card = Card.mine.contains(lastCard) ? lastCard : (Card.mine.first ?? .other)
                amountFocused = true
            }
            .sensoryFeedback(.success, trigger: saved)
            .alert("Couldn't Save Purchase", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
        }
    }

    /// Anything typed that would be lost by closing the sheet.
    private var hasInput: Bool {
        !amountText.isEmpty || !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            || !note.trimmingCharacters(in: .whitespaces).isEmpty
            || !quick.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Big centred amount like Cash App, with a small currency switch below.
    private var amountField: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Self.symbol(currency))
                    .font(.title.weight(.bold))
                    .foregroundStyle(amountText.isEmpty ? .tertiary : .secondary)
                // Sized by a hidden copy of the text, so the field always
                // grows to fit an amount filled in from Quick entry or a scan.
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.money)
                    .hidden()
                    .overlay(alignment: .leading) {
                        TextField("0", text: $amountText)
                            .font(.money)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .accessibilityLabel("Amount in \(currency)")
                    }
                    .padding(.trailing, 4)
            }
            .onChange(of: amountText) { old, new in
                // Under 1,000,000 with at most two decimals; anything else
                // typed is ignored.
                guard !Self.isTypeable(new) else { return }
                amountText = Self.isTypeable(old) ? old : ""
                refusedKeys += 1
            }
            .sensoryFeedback(.impact(weight: .light), trigger: refusedKeys)
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
                    // At accessibility sizes the words wrap whole, centred.
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .surface(radius: 20)
            }
            .buttonStyle(.plain)

            if scanned {
                Label("Filled in from your receipt. Check it before you add.", systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Fills in what the scan found. Never saves: Raj checks and taps the tick.
    private func apply(_ r: ReceiptReading) {
        if let amount = r.amount {
            amountText = AmountParser.parse(amount).map { QuickEntry.fieldText($0.amount) } ?? amount
        }
        if let code = r.currency, Self.currencies.contains(code) { currency = code }
        if let name = r.merchant { merchant = name }   // suggests a category via onChange
        if let when = r.date { date = min(when, .now) }
        if let found = CardBook.shared.card(last4: r.last4), Card.mine.contains(found) { card = found }
        amountFocused = false
        scanned = true
    }

    private static func symbol(_ code: String) -> String { Money.symbol(code) }

    private var parsedAmount: Decimal? {
        guard let r = AmountParser.parse(amountText), r.amount > 0, r.amount < QuickEntry.limit else { return nil }
        return r.amount
    }

    /// What the amount field accepts: the shared rule, with 6 whole digits
    /// because this sheet saves under 1,000,000 (`parsedAmount`).
    nonisolated static func isTypeable(_ text: String) -> Bool { AmountEntry.isTypeable(text, wholeDigits: 6) }

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
        // A double tap on Add must not save twice: hand-typed purchases are
        // never merged as duplicates, so nothing else would catch it.
        guard saved == 0, let amount = parsedAmount else { return }
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
            // Counts only: never the amount, shop or note.
            Analytics.shared.track(.purchaseAddedManually, ["category_changed": .bool(categoryTouched),
                                                            "has_note": .bool(!noteToSave.isEmpty)])
            Task { await FXService.backfill(in: context) }
            dismiss()
        } catch {
            log.error("Manual add failed: \(error.localizedDescription)")
            saveError = "Please try again."
        }
    }
}
