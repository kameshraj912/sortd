import SwiftUI

/// Monzo-style: one big centred number you can edit, quick preset chips,
/// a solid Save pill and an outlined Remove.
struct BudgetSheet: View {
    @Binding var budget: Double
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = 0
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let presets: [Double] = [500, 800, 1000, 1500, 2000]

    /// The largest monthly budget Sortd accepts: 1,000,000, scaled up for
    /// currencies with big numbers (the same steps as the setup presets, so
    /// a ₩3,000,000 or Rp30,000,000 budget still fits). Anything bigger is a
    /// typo, and huge values used to crash this sheet when turned into text.
    static func maxBudget(_ currency: String = Money.home) -> Double {
        1_000_000 * currencyScale(currency)
    }

    /// Round-number steps for currencies with big numbers.
    static func currencyScale(_ currency: String) -> Double {
        ["JPY": 100, "KRW": 1000, "IDR": 10000, "INR": 50, "PHP": 40, "THB": 25, "HUF": 250, "ISK": 100][currency] ?? 1
    }

    /// A stored budget that is safe to show: bad values (too big, NaN,
    /// infinity, negative) become 0 so a broken install recovers.
    static func sanitized(_ budget: Double, currency: String = Money.home) -> Double {
        guard budget.isFinite, budget > 0, budget <= maxBudget(currency) else { return 0 }
        return budget
    }

    /// Text for the field. Never uses Int(), which traps on huge values.
    static func text(for budget: Double, currency: String = Money.home) -> String {
        let safe = sanitized(budget, currency: currency)
        guard safe > 0 else { return "" }
        return safe.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    /// Keeps what was typed to the digits the limit allows before the decimal
    /// point (7 for 1,000,000) and 2 after, and never more than the limit.
    static func limitInput(_ raw: String, currency: String = Money.home) -> String {
        let limit = maxBudget(currency)
        let maxDigits = String(format: "%.0f", limit).count
        var whole = ""
        var fraction: String?
        for ch in raw {
            if ch.isASCII, ch.isNumber {
                if fraction == nil {
                    if whole.count < maxDigits { whole.append(ch) }
                } else if fraction!.count < 2 {
                    fraction!.append(ch)
                }
            } else if ch == "." || ch == ",", fraction == nil {
                fraction = ""
            }
        }
        // Drop leading zeros ("0005" → "5") but keep a single "0".
        while whole.count > 1, whole.first == "0" { whole.removeFirst() }
        if let w = Double(whole), w >= limit { return String(format: "%.0f", limit) }
        guard let fraction else { return whole }
        return (whole.isEmpty ? "0" : whole) + "." + fraction
    }

    private var value: Double {
        Self.sanitized((AmountParser.parse(text)?.amount.double) ?? 0)
    }

    private var range: String {
        let month = Calendar.current.dateInterval(of: .month, for: .now)
        let start = (month?.start ?? .now).formatted(.dateTime.day().month(.abbreviated))
        let end = (month?.end.addingTimeInterval(-1) ?? .now).formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end) · all cards"
    }

    var body: some View {
        Group {
            // At accessibility sizes the sheet is full height and scrolls,
            // so nothing is cut to "Remove Bud..." (UI pass finding 5).
            if typeSize.isAccessibilitySize {
                ScrollView { content }
            } else {
                content
            }
        }
        .padding(20)
        .onAppear {
            // Recover installs that saved a huge or broken budget.
            let safe = Self.sanitized(budget)
            if safe != budget { budget = safe }
            if safe > 0 { text = Self.text(for: safe) }
        }
        .toolbar {
            // The number pad has no Return key; without this there is
            // no way to put it away and reach Save underneath.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }.fontWeight(.semibold)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(420), .large])
        // Solid, so the cards behind don't bleed through the glass.
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var content: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Text("Monthly Budget")
                    .font(.headline)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Money.symbol(Money.home))
                        .font(.title.weight(.bold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                    TextField("0", text: $text)
                        .font(.money)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .fixedSize()
                        .onChange(of: text) { _, new in
                            let limited = Self.limitInput(new)
                            if limited != new { text = limited }
                        }
                        .accessibilityLabel("Monthly budget in \(Locale.current.localizedString(forCurrencyCode: Money.home) ?? Money.home)")
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .onTapGesture { focused = true }
                Text(range)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Quick presets, like the gift-budget chips.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        let selected = value == preset
                        Button {
                            text = Self.text(for: preset)
                        } label: {
                            Text(Money.format(Decimal(preset), Money.home, cents: false))
                                .chip(selected: selected)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    budget = value
                    saved += 1
                    dismiss()
                } label: {
                    Text("Save")
                        .primaryPill(enabled: value > 0)
                }
                .primaryGlass()
                .disabled(value <= 0)

                if budget > 0 {
                    Button {
                        budget = 0
                        dismiss()
                    } label: {
                        Text("Remove Budget")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.primary)
                            .overlay(Capsule().strokeBorder(Color.primary, lineWidth: 1.5))
                    }
                }
            }
            .buttonStyle(.pressable)
        }
    }
}
