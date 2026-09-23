import SwiftUI

/// Grey bars behind "Nothing spent yet", like an empty Insights screen.
struct PlaceholderBars: View {
    private let heights: [CGFloat] = [0.55, 0.8, 0.35, 0.6, 0.9, 0.45, 0.7]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(heights.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(height: geo.size.height * heights[i])
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay {
                Label("Nothing spent yet", systemImage: "leaf")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground), in: .capsule)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing spent in this period yet")
    }
}

/// Swipeable cards, like the Stocks "Most active" carousel: top merchants,
/// biggest purchases, and delivery vs eating out this month.
struct InsightCarousel: View {
    let transactions: [Transaction]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Row: Identifiable {
        let id = UUID()
        let category: SpendCategory
        let title: String
        let detail: String
        let amount: Decimal
    }

    private var topMerchants: [Row] {
        Dictionary(grouping: transactions) { $0.merchant }
            .map { name, items in
                Row(category: items[0].category, title: name,
                    detail: items.count == 1 ? "1 purchase" : "\(items.count) purchases", amount: items.audTotal)
            }
            .sorted { $0.amount > $1.amount }
            .prefix(3)
            .map { $0 }
    }

    private var biggest: [Row] {
        // Transfers (top-ups, moving money between accounts) and refunds aren't purchases.
        transactions.filter { $0.category != .transfers && !$0.refunded }
            .sorted { $0.audValue > $1.audValue }.prefix(3).map {
            Row(category: $0.category, title: $0.merchant,
                detail: $0.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                amount: $0.audValue)
        }
    }

    private var food: [Row] {
        [SpendCategory.foodDelivery, .eatingOut].map { category in
            let items = transactions.filter { $0.category == category }
            let average = items.isEmpty ? 0 : items.audTotal / Decimal(items.count)
            return Row(category: category, title: category.name,
                       detail: items.isEmpty ? "None yet"
                           : items.count == 1 ? "1 time"
                           : "\(items.count) times · about \(Money.format(average, Money.home)) each",
                       amount: items.audTotal)
        }
    }

    var body: some View {
        if !transactions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Highlights")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        card("Top Shops", nil, topMerchants)
                        card("Biggest Purchases", nil, biggest)
                        card("Food", "Delivery vs eating out", food)
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    private func card(_ title: String, _ subtitle: String?, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { row in
                // At accessibility sizes the amount drops under the name so
                // neither gets squeezed to "…".
                let large = dynamicTypeSize.isAccessibilitySize
                let layout = large
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    HStack(spacing: 10) {
                        CategoryIcon(category: row.category, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title).font(.subheadline.weight(.semibold))
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(large ? 3 : 1)
                    }
                    if !large { Spacer(minLength: 4) }
                    Text(Money.format(row.amount, Money.home))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 230, alignment: .topLeading)
        // Five sixths of the row, so the next card peeks in on every phone.
        .containerRelativeFrame(.horizontal, count: 6, span: 5, spacing: 12, alignment: .topLeading)
        .surface()
    }
}
