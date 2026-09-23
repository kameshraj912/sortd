import SwiftUI
import SwiftData

/// Settings › Learned Categories: merchants Sortd has learned a category for,
/// from you correcting a purchase.
struct LearnedRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MerchantRule.key) private var rules: [MerchantRule]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var body: some View {
        let names = shopNames
        List {
            ListPageTitle(title: "Learned Categories")
            if rules.isEmpty {
                EmptyState("Nothing learned yet", symbol: "tag",
                           message: "Change a purchase's category and Sortd remembers it for that shop.")
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(rules) { rule in
                        HStack(spacing: 12) {
                            CategoryIcon(category: rule.category, size: 30)
                            Text(names[rule.key] ?? rule.key.capitalized)
                            Spacer()
                            Text(rule.category.name).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(rules[i]) }
                        try? context.save()
                    }
                } footer: {
                    Text("Swipe left to forget one.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Learned Categories")
    }

    /// A rule only stores its key ("sevenseedscoffee", see `MerchantName.key`).
    /// Show the shop's name from the latest purchase with that key instead.
    /// Rules are keyed on the raw or the cleaned name, so both are checked.
    private var shopNames: [String: String] {
        var names: [String: String] = [:]
        for t in transactions where !t.merchant.isEmpty {
            for key in [MerchantName.key(t.rawMerchant), MerchantName.key(t.merchant)] where names[key] == nil {
                names[key] = t.merchant
            }
        }
        return names
    }
}
