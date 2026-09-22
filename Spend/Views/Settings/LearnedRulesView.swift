import SwiftUI
import SwiftData

/// Settings › Categories: merchants Sortd has learned a category for, from
/// you correcting a purchase.
struct LearnedRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MerchantRule.key) private var rules: [MerchantRule]

    var body: some View {
        List {
            ListPageTitle(title: "Learned Categories", subtitle: "Categories you've set for a merchant are used next time.")
            if rules.isEmpty {
                ContentUnavailableView(
                    "Nothing Learned Yet",
                    systemImage: "brain",
                    description: Text("Change a purchase’s category and Sortd will remember it for that merchant.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(rules) { rule in
                HStack(spacing: 12) {
                    CategoryIcon(category: rule.category, size: 30)
                    Text(rule.key)
                    Spacer()
                    Text(rule.category.name).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(rules[i]) }
                try? context.save()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Learned Categories")
    }
}
