import SwiftUI

enum Money {
    nonisolated static let homeKey = "homeCurrency"

    /// The currency totals are shown in. Set during setup (detected from the
    /// phone) and changeable in Settings. Every purchase also keeps its own
    /// currency; `audAmount`/`audValue` hold the value in this currency.
    nonisolated static var home: String {
        UserDefaults.standard.string(forKey: homeKey) ?? detectedHome
    }

    /// The phone's own currency, if we have daily rates for it.
    nonisolated static var detectedHome: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return supported.contains(code) ? code : "USD"
    }

    /// Currencies with daily ECB rates (via Frankfurter).
    nonisolated static let supported = ["AUD", "SGD", "USD", "EUR", "GBP", "JPY", "MYR", "NZD", "CAD", "CHF", "CNY", "HKD",
                                        "INR", "IDR", "KRW", "PHP", "THB", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF",
                                        "ILS", "MXN", "BRL", "ZAR", "TRY", "RON", "ISK", "BGN"]

    static func format(_ value: Decimal, _ code: String, cents: Bool = true) -> String {
        // The home currency gets its plain local symbol ("$", "£"); others are
        // always spelled out ("S$", "US$") so two dollars can't be confused.
        let dollars = ["AUD", "SGD", "USD", "NZD", "CAD", "HKD"]
        let foreign = ["AUD": "A$", "SGD": "S$", "USD": "US$", "MYR": "RM", "NZD": "NZ$", "CAD": "C$", "HKD": "HK$"]
        let symbol: String? = code == home ? (dollars.contains(code) ? "$" : (code == "MYR" ? "RM" : nil)) : foreign[code]
        guard let symbol else {
            return value.formatted(.currency(code: code).precision(.fractionLength(cents ? 2 : 0)))
        }
        let sign = value < 0 ? "-" : ""
        let n = (value < 0 ? -value : value).formatted(.number.precision(.fractionLength(cents ? 2 : 0)))
        return "\(sign)\(symbol)\(n)"
    }

    /// Just the symbol, for amount entry fields ("$", "S$", "£").
    static func symbol(_ code: String) -> String {
        let text = format(0, code, cents: false)
        return String(text.prefix { !$0.isNumber })
    }

    /// Whole units for headline totals once they're big enough.
    static func headline(_ value: Decimal) -> String {
        format(value, home, cents: value < 1000)
    }
}

/// Soft tinted rounded square with the symbol in the category's colour.
struct CategoryIcon: View {
    let category: SpendCategory
    var size: CGFloat = 40
    /// Grows with Dynamic Type, capped so rows stay usable at huge sizes.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = size * 0.9 * min(scale, 1.6)
        Image(systemName: category.symbol)
            .font(.system(size: side * 0.42, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: side, height: side)
            .background(category.color.opacity(scheme == .dark ? 0.22 : 0.14),
                        in: .rect(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    var showTime = true
    /// Off on a category's own screen, where it would repeat on every row.
    var showCategory = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Side by side normally; at the largest text sizes, stacked so
        // nothing is cut off (Apple's own lists do the same).
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if !big { CategoryIcon(category: transaction.category) }

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(big ? 3 : 1)
                Text(showCategory ? "\(transaction.category.name) · \(transaction.paidWithLabel)" : transaction.paidWithLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(big ? 3 : 1)
            }

            if !big { Spacer(minLength: 8) }

            VStack(alignment: big ? .leading : .trailing, spacing: 3) {
                if transaction.needsReview {
                    Label("Add amount", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("-" + Money.format(transaction.amount, transaction.currencyCode))
                        .font(.body)
                        .foregroundStyle(transaction.refunded ? .secondary : .primary)
                        .strikethrough(transaction.refunded)
                        .monospacedDigit()
                }
                Text(trailingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Under the amount: the AUD value for foreign purchases, otherwise when.
    private var trailingDetail: String {
        if transaction.refunded { return "Refunded" }
        if transaction.currencyCode != Money.home, !transaction.needsReview {
            return transaction.needsRate ? "Converting…" : "≈ " + Money.format(transaction.audValue, Money.home)
        }
        return showTime ? transaction.date.formatted(date: .omitted, time: .shortened) : shortDay
    }

    private var shortDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(transaction.date) { return "Today" }
        if cal.isDateInYesterday(transaction.date) { return "Yesterday" }
        return transaction.date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private var accessibilityText: String {
        var parts = [
            transaction.merchant,
            transaction.needsReview ? "amount missing" : Money.format(transaction.amount, transaction.currencyCode),
            transaction.category.name,
            transaction.paidWithLabel,
        ]
        if transaction.currencyCode != Money.home, !transaction.needsRate {
            parts.insert("about \(Money.format(transaction.audValue, Money.home))", at: 2)
        }
        return parts.joined(separator: ", ")
    }
}

extension Collection where Element == Transaction {
    /// Spending in AUD. Transfers (card top-ups, moving money between your
    /// own accounts) are left out, or money moved NAB → YouTrip and then
    /// spent would be counted twice.
    var audTotal: Decimal { reduce(0) { $1.category == .transfers ? $0 : $0 + $1.audValue } }
}

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}
