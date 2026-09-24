import SwiftUI

/// The short sheet shown when a locked feature is tapped: that feature's
/// preview, yearly or monthly, and the buy button. "See all plans" opens
/// the full flow in the same sheet, at the plans step (with Lifetime).
struct FeaturePaywallSheet: View {
    let feature: ProStore.Feature

    @Environment(\.dismiss) private var dismiss
    @State private var store = PaywallStore()
    @State private var showingAll = false
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    private var page: PaywallPage { PaywallPage(feature) }
    /// Yearly and monthly here; Lifetime is one tap away.
    private var shortList: [PaywallPlan] { store.plans.filter { $0.kind != .lifetime } }

    var body: some View {
        Group {
            if showingAll {
                PaywallFlow(start: .plans, store: store, onClose: { dismiss() })
                    .presentationDetents([.large])
            } else {
                compact
                    // As tall as it needs; a scrolling full-height sheet
                    // when that doesn't fit (small phones, large text).
                    .presentationDetents([.height(max(contentHeight + footerHeight + 52, 320))])
            }
        }
        .presentationDragIndicator(.visible)
        .task { if !store.loaded { await store.load() } }
        .onChange(of: store.pro.isPro) { _, pro in if pro { dismiss() } }
    }

    private var compact: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sortd Pro")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(page.headline)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(page.sentence)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PaywallPreview(page: page, compact: true)
                        .padding(16)
                        .surface(radius: 16)

                    if shortList.isEmpty {
                        HStack(spacing: 10) {
                            if !store.loaded || store.pro.isLoading { ProgressView() }
                            Text(store.loadError ?? "Loading plans…").font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .surface(radius: 16)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(shortList) { plan in
                                PlanRow(plan: plan, selected: store.selectedPlan?.id == plan.id) { store.selected = plan.id }
                            }
                        }
                    }

                    Button("See All Plans") { withAnimation(.snappy) { showingAll = true } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    PurchaseLinks(store: store)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)

            PurchaseFooter(store: store, onPurchased: { dismiss() })
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .background(Color.page)
        .tint(Color.ink)
    }
}
