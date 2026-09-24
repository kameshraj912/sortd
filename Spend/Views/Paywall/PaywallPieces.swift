import SwiftUI
import StoreKit

enum PaywallLinks {
    static let terms = URL(string: "https://sortd.page/terms.html")!
    static let privacy = URL(string: "https://sortd.page/privacy")!
}

/// What the paywall screens share: the plans, the selected one, and the
/// buy / restore calls. Every purchase goes through `ProStore`.
@MainActor
@Observable
final class PaywallStore {
    let pro = ProStore.shared
    private(set) var plans: [PaywallPlan] = []
    var selected = ProStore.ID.yearly
    private(set) var working = false
    var message: String?
    /// False when notifications are off for Sortd: the trial timeline then
    /// doesn't promise a reminder.
    private(set) var canRemind = true
    private(set) var loaded = false

    var selectedPlan: PaywallPlan? { plans.first { $0.id == selected } ?? plans.first }
    var yearly: PaywallPlan? { plans.first { $0.kind == .yearly } }
    /// The trial on the yearly plan, when this person can still get it.
    var trial: TrialPeriod? { yearly?.trial }
    /// Until the App Store answers, assume the trial (most people get it):
    /// the step count then only changes for someone who already used it.
    var steps: [PaywallStep] { PaywallStep.sequence(hasTrial: !loaded || trial != nil) }
    var loadError: String? { plans.isEmpty && loaded ? pro.loadError : nil }

    func load() async {
        working = true
        defer { working = false }
        await pro.load()
        plans = await pro.paywallPlans()
        #if DEBUG
        if plans.isEmpty, ProcessInfo.processInfo.environment["SPEND_PAYWALL_DEMO"] == "1" {
            plans = Self.samplePlans
        }
        #endif
        canRemind = await Reminders.canPromiseReminder()
        loaded = true
    }

    /// True when Pro is now unlocked.
    func buy() async -> Bool {
        guard let plan = selectedPlan else { return false }
        guard let product = plan.product else {
            message = "Plans are still loading from the App Store."
            return false
        }
        working = true; message = nil
        defer { working = false }
        do {
            switch try await pro.buy(product) {
            case .purchased: return true
            case .pending: message = "Waiting for approval (for example Ask to Buy). Pro unlocks as soon as it's approved."
            case .cancelled: break
            }
        } catch {
            message = error.localizedDescription
        }
        return false
    }

    func restore() async {
        working = true; message = nil
        defer { working = false }
        do {
            try await pro.restore()
            message = pro.isPro ? nil : "No purchases found for this Apple Account."
        } catch {
            message = "Couldn't restore right now. Please try again."
        }
    }

    #if DEBUG
    /// DEBUG screenshots when the App Store returns nothing (SPEND_PAYWALL_DEMO=1).
    static var samplePlans: [PaywallPlan] {
        let f = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        return [
            PaywallPlan(id: ProStore.ID.yearly, kind: .yearly, displayPrice: "$49.99", price: 49.99, format: f,
                        trial: TrialPeriod(value: 2, unit: .week)),
            PaywallPlan(id: ProStore.ID.monthly, kind: .monthly, displayPrice: "$6.99", price: 6.99, format: f),
            PaywallPlan(id: ProStore.ID.lifetime, kind: .lifetime, displayPrice: "$99.99", price: 99.99, format: f),
        ]
    }
    #endif
}

/// Title, the logo bar and one line under it: the setup screens' header.
struct PaywallHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            BrandBar(width: 14, height: 3)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One plan: a radio mark, the name and what it includes, the price.
struct PlanRow: View {
    let plan: PaywallPlan
    let selected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            let big = typeSize.isAccessibilitySize
            let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.ink : Color.secondary.opacity(0.5))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(plan.title).font(.subheadline.weight(.semibold))
                            if plan.kind == .yearly {
                                Text("Best value")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.track, in: .capsule)
                            }
                        }
                        Text(plan.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !big { Spacer(minLength: 8) }
                VStack(alignment: big ? .leading : .trailing, spacing: 1) {
                    Text(plan.displayPrice)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(plan.priceUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, big ? 36 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.ink : Color.hairline, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.title), \(plan.displayPrice) \(plan.priceUnit)")
        .accessibilityValue(plan.detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The buy button with Apple's required details right under it: price,
/// length and renewal. Pinned at the bottom of the screen.
struct PurchaseFooter: View {
    @Bindable var store: PaywallStore
    /// Called once Pro is unlocked.
    let onPurchased: () -> Void

    var body: some View {
        let plan = store.selectedPlan
        VStack(spacing: 10) {
            if let message = store.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // No plans because the App Store couldn't be reached: the button retries.
            let failed = plan == nil && store.loadError != nil
            Button {
                if failed { Task { await store.load() } }
                else { Task { if await store.buy() { onPurchased() } } }
            } label: {
                ZStack {
                    if store.working { ProgressView().tint(Color.onBrand) }
                    else { Text(plan?.buttonTitle ?? (failed ? "Try Again" : "Loading Plans…")) }
                }
                .primaryPill(enabled: plan != nil || failed)
            }
            .buttonStyle(.plain)
            .disabled((plan == nil && !failed) || store.working)

            if let plan {
                Text(plan.terms)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Restore Purchases, Redeem Code, Terms and Privacy. Scrolls with the
/// plans so the pinned footer stays short on small phones and large text.
struct PurchaseLinks: View {
    @Bindable var store: PaywallStore
    @Environment(\.openURL) private var openURL
    @State private var redeeming = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { restore; redeem; terms; privacy }
            VStack(spacing: 6) {
                HStack(spacing: 16) { restore; redeem }
                HStack(spacing: 16) { terms; privacy }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .redeemOfferCode(isPresented: $redeeming) { store.message = $0 }
    }

    private var restore: some View {
        Button("Restore Purchases") { Task { await store.restore() } }.fixedSize()
    }
    private var redeem: some View {
        Button("Redeem Code") { store.message = nil; redeeming = true }.fixedSize()
    }
    private var terms: some View {
        Button("Terms") { openURL(PaywallLinks.terms) }.fixedSize()
    }
    private var privacy: some View {
        Button("Privacy") { openURL(PaywallLinks.privacy) }.fixedSize()
    }
}

/// Today → reminder → trial ends, joined by a line.
struct TrialTimelineView: View {
    let timeline: TrialTimeline
    @ScaledMetric(relativeTo: .subheadline) private var marker: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(timeline.items.enumerated()), id: \.element.id) { index, item in
                let last = index == timeline.items.count - 1
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        icon(item.kind)
                            .frame(width: marker, height: marker)
                        if !last {
                            Rectangle().fill(Color.track).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                        layout {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Text(item.kind == .today ? "Now" : item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, last ? 0 : 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title), \(item.kind == .today ? "today" : item.date.formatted(date: .complete, time: .omitted)). \(item.detail)")
            }
        }
    }

    @ViewBuilder
    private func icon(_ kind: TrialTimeline.Item.Kind) -> some View {
        let symbol = switch kind {
        case .today: "lock.open.fill"
        case .reminder: "bell.fill"
        case .ends: "calendar"
        }
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(kind == .today ? Color.onBrand : Color.ink)
            .frame(width: marker, height: marker)
            .background(kind == .today ? Color.brand : Color.card, in: .circle)
            .overlay(Circle().strokeBorder(kind == .today ? Color.clear : Color.hairline, lineWidth: 1))
    }
}
