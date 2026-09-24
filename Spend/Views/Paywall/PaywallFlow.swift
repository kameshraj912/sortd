import SwiftUI

/// Opens the right Sortd Pro screen for where it was asked for: the beta
/// note, the thank-you sheet, the multi-step flow, the single page, or the
/// short sheet for one locked feature. Use this rather than `PaywallView`.
struct ProPaywall: View {
    let entry: PaywallEntry
    @Environment(\.dismiss) private var dismiss
    /// Decided once, so buying doesn't swap the screen mid-purchase.
    @State private var presentation: PaywallPresentation

    init(entry: PaywallEntry) {
        self.entry = entry
        let pro = ProStore.shared
        _presentation = State(initialValue: PaywallPresentation.make(
            entry: entry, variant: .current, betaFree: pro.isBetaFree, isPro: pro.isPro))
    }

    var body: some View {
        switch presentation {
        case .betaNote, .owned, .singlePage:
            PaywallView(feature: feature)
        case .steps:
            PaywallFlow(onClose: { dismiss() })
        case .compact(let feature):
            FeaturePaywallSheet(feature: feature)
        }
    }

    private var feature: ProStore.Feature? {
        if case .feature(let f) = entry { return f }
        return nil
    }
}

/// Sortd Pro in three short steps: what you get, how the free trial works,
/// pick a plan. Laid out like first-launch setup (same top bar, header and
/// bottom button) so it reads as part of the app.
struct PaywallFlow: View {
    var start: PaywallStep = .features
    /// "Not Now" in setup; nil shows a close (×) button.
    var closeTitle: String? = nil
    /// Setup only: Back on the first step goes to the step before the paywall.
    var onBack: (() -> Void)? = nil
    /// Closed, skipped, or bought.
    let onClose: () -> Void

    @State private var store: PaywallStore
    @State private var step: PaywallStep
    @State private var forward = true
    @State private var page: PaywallPage?

    init(start: PaywallStep = .features, startPage: PaywallPage? = nil, closeTitle: String? = nil,
         store: PaywallStore? = nil, onBack: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.start = start
        self.closeTitle = closeTitle
        self.onBack = onBack
        self.onClose = onClose
        _store = State(initialValue: store ?? PaywallStore())
        _step = State(initialValue: start)
        _page = State(initialValue: startPage)
    }

    private var pages: [PaywallPage] { PaywallPage.available(gmail: Features.gmail) }
    private var index: Int { store.steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .background(Color.page)
        .tint(Color.ink)
        .task { if !store.loaded { await store.load() } }
        // No trial for this Apple Account: the trial step would describe
        // something that won't happen.
        .onChange(of: store.steps) { _, steps in
            if !steps.contains(step) { step = .plans }
        }
        .onChange(of: store.pro.isPro) { _, pro in if pro { onClose() } }
        .sensoryFeedback(.selection, trigger: step)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if index > 0 || onBack != nil {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            HStack(spacing: 4) {
                ForEach(store.steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.brandPalette[i % Color.brandPalette.count] : Color.track)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(store.steps.count)")
            if let closeTitle {
                Button(closeTitle, action: onClose)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if step == .plans {
                PurchaseFooter(store: store, onPurchased: onClose)
            } else {
                Button { go(1) } label: { Text("Continue").primaryPill() }
                    .buttonStyle(.plain)
                if step == .features {
                    Text("Apple Pay logging, cards and export stay free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.page)
    }

    private func go(_ delta: Int) {
        let steps = store.steps
        let next = min(max(index + delta, 0), steps.count - 1)
        forward = delta > 0
        withAnimation(.snappy) { step = steps[next] }
    }

    private func back() {
        if index == 0 { onBack?() } else { go(-1) }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .features: featuresStep
        case .trial: trialStep
        case .plans: plansStep
        }
    }

    private var featuresStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaywallHeader(title: "What you get with Pro",
                          subtitle: "More ways to log spending, and a clearer view of it.")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(pages) { p in
                            FeaturePage(page: p)
                                .padding(.horizontal, 20)
                                .containerRelativeFrame(.horizontal)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .id(p)
                        }
                    }
                    // Every page as tall as the tallest, so text lines up across pages.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
                .sensoryFeedback(.selection, trigger: page)
                // A start page (DEBUG screenshots) isn't scrolled to by scrollPosition alone.
                .onAppear { if let page { proxy.scrollTo(page, anchor: .leading) } }
            }

            PageDots(count: pages.count, current: pages.firstIndex(of: page ?? pages[0]) ?? 0)
        }
    }

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaywallHeader(title: "How the free trial works",
                          subtitle: "Nothing to pay today. Cancel any time before it ends.")
            if let trial = store.trial, let yearly = store.yearly {
                TrialTimelineView(timeline: TrialTimeline(start: .now, trial: trial, plan: yearly, canRemind: store.canRemind))
                    .padding(16)
                    .surface(radius: 16)
                Text("Cancel in Settings › Apple Account › Subscriptions. The trial is on the yearly plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var plansStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaywallHeader(title: "Choose your plan", subtitle: "Every plan unlocks everything in Pro.")
            if store.plans.isEmpty {
                HStack(spacing: 10) {
                    if !store.loaded || store.pro.isLoading { ProgressView() }
                    Text(store.loadError ?? "Loading plans…").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .surface(radius: 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.plans) { plan in
                        PlanRow(plan: plan, selected: store.selectedPlan?.id == plan.id) { store.selected = plan.id }
                    }
                }
            }
            PurchaseLinks(store: store)
        }
    }
}

/// One "What you get" page: the preview in a card, then a short headline
/// and one sentence.
struct FeaturePage: View {
    let page: PaywallPage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaywallPreview(page: page)
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .center)
                .surface(radius: 16)
            VStack(alignment: .leading, spacing: 4) {
                Label(page.headline, systemImage: page.symbol)
                    .font(.headline)
                    .labelStyle(PaywallLabelStyle())
                Text(page.sentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Icon and title on one baseline, the icon a fixed column.
private struct PaywallLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Color.ink)
            configuration.title
        }
    }
}

/// Wallet-style page dots, as under the cards on Home.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.ink : Color.track)
                    .frame(width: i == current ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
