import SwiftUI
import Charts

/// The small picture on each "What you get" page, drawn with the app's own
/// rows and chart style (TransactionRow, CategoryIcon, the Insights line),
/// so it looks like Sortd rather than marketing art. Sample values only:
/// none of this touches the person's data.
struct PaywallPreview: View {
    let page: PaywallPage
    /// One row and a shorter chart, for the single-feature sheet.
    var compact = false
    @State private var samples = PaywallSamples()

    var body: some View {
        Group {
            switch page {
            case .gmail: gmail
            case .camera: camera
            case .insights: insights
            case .bills: bills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func source(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }

    private var gmail: some View {
        VStack(alignment: .leading, spacing: 0) {
            source("Found in Gmail", "envelope")
            TransactionRow(transaction: samples.uberEats, subtitle: "From Gmail")
            if !compact {
                Divider().padding(.vertical, 8)
                TransactionRow(transaction: samples.icloud, subtitle: "From Gmail")
            }
        }
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: 0) {
            source("Read from a receipt", "doc.text.viewfinder")
            TransactionRow(transaction: samples.groceries, subtitle: "Scanned")
            if !compact {
                Divider().padding(.vertical, 8)
                TransactionRow(transaction: samples.hardware, subtitle: "Scanned")
            }
        }
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This month").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(Money.format(1182.45, Money.home))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            MiniSpendChart()
                .frame(height: compact ? 44 : 64)
            Divider()
            BudgetPreviewRow(category: .eatingOut, spent: 180, limit: 250)
        }
    }

    private var bills: some View {
        VStack(alignment: .leading, spacing: 0) {
            source("Coming up", "bell")
            ForEach(Array(samples.upcoming.prefix(compact ? 2 : 3).enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().padding(.leading, 48) }
                HStack(spacing: 12) {
                    CategoryIcon(category: item.category, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.merchant).font(.subheadline)
                        Text(item.when).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(Money.format(item.amount, Money.home))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var accessibilityText: String {
        switch page {
        case .gmail: compact ? "Example: an Uber Eats order found in Gmail." : "Example: an Uber Eats order and an iCloud receipt, found in Gmail."
        case .camera: compact ? "Example: a Woolworths purchase read from a paper receipt." : "Example: two purchases read from paper receipts."
        case .insights: "Example: this month's spending line, and eating out at 180 of a 250 limit."
        case .bills: compact ? "Example: Netflix due tomorrow, and Spotify coming up." : "Example: Netflix due tomorrow, and two more bills coming up."
        }
    }
}

/// Sample purchases for the previews. Never saved: they have no model context.
struct PaywallSamples {
    let uberEats: Transaction
    let icloud: Transaction
    let groceries: Transaction
    let hardware: Transaction
    let upcoming: [(merchant: String, when: String, amount: Decimal, category: SpendCategory)]

    init(now: Date = .now) {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now }
        func make(_ merchant: String, _ amount: Decimal, _ category: SpendCategory, _ source: TxnSource, _ date: Date) -> Transaction {
            Transaction(date: date, merchant: merchant, amount: amount, currencyCode: Money.home,
                        card: .other, category: category, source: source)
        }
        uberEats = make("Uber Eats", 31.40, .foodDelivery, .email, at(12, 54))
        icloud = make("iCloud+", 4.49, .subscriptions, .email, at(8, 2))
        groceries = make("Woolworths", 58.30, .groceries, .manual, at(17, 41))
        hardware = make("Bunnings", 24.95, .shopping, .manual, at(11, 15))
        let friday = cal.date(byAdding: .day, value: 4, to: now) ?? now
        upcoming = [
            ("Netflix", "Tomorrow", 18.99, .subscriptions),
            ("Spotify", friday.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), 13.99, .entertainment),
            ("Electricity", "In 9 days", 142.60, .bills),
        ]
    }
}

/// The Insights line in miniature: this month solid, last month dashed.
private struct MiniSpendChart: View {
    private struct Point: Identifiable {
        let day: Int
        let total: Double
        var id: Int { day }
    }

    // Running totals: a plausible month, shaped like the demo data's.
    private static let current: [Point] = [40, 110, 150, 210, 260, 300, 380, 410, 470, 520, 600, 640,
                                           700, 760, 800, 860, 930, 990, 1040, 1100, 1150, 1182]
        .enumerated().map { Point(day: $0.offset + 1, total: $0.element) }
    private static let previous: [Point] = [30, 90, 140, 170, 240, 280, 320, 360, 420, 440, 480, 520, 560,
                                            600, 640, 660, 700, 720, 740, 760, 790, 820, 840, 860, 880, 900,
                                            930, 950, 970, 990]
        .enumerated().map { Point(day: $0.offset + 1, total: $0.element) }

    var body: some View {
        Chart {
            ForEach(Self.previous) { p in
                LineMark(x: .value("Day", p.day), y: .value("Spent", p.total), series: .value("Period", "previous"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(Self.current) { p in
                AreaMark(x: .value("Day", p.day), y: .value("Spent", p.total))
                    .foregroundStyle(Color.ink.opacity(0.06))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.day), y: .value("Spent", p.total), series: .value("Period", "current"))
                    .foregroundStyle(Color.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = Self.current.last {
                PointMark(x: .value("Day", last.day), y: .value("Spent", last.total))
                    .foregroundStyle(Color.ink)
                    .symbolSize(36)
            }
        }
        .chartXScale(domain: 1...30)
        .chartYScale(domain: 0...1250)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// One category against its limit, as in Insights › Categories.
private struct BudgetPreviewRow: View {
    let category: SpendCategory
    let spent: Decimal
    let limit: Decimal

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.name).font(.subheadline)
                    Spacer(minLength: 8)
                    Text("\(Money.format(spent, Money.home, cents: false)) of \(Money.format(limit, Money.home, cents: false))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.track)
                        Capsule().fill(category.color)
                            .frame(width: geo.size.width * CGFloat((spent / limit).double))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}
