import SwiftUI
import StoreKit

/// One plan as shown on the paywall: from the App Store, or sample values
/// for DEBUG screenshots (SPEND_PAYWALL_DEMO=1).
struct PlanDisplay: Identifiable {
    let id: String
    let price: String
    let perMonth: String?
    let trial: String?
    let product: Product?
}

/// Sortd Pro sheet. Shows real prices from the App Store, the free trial when
/// the person is eligible, and Apple's required renewal terms.
struct PaywallView: View {
    /// The feature that was tapped, shown first. Nil when opened from Settings.
    var feature: ProStore.Feature? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = ProStore.shared
    @State private var selected = ProStore.ID.yearly
    @State private var trials: [String: String] = [:]
    @State private var working = false
    @State private var message: String?

    private var features: [ProStore.Feature] {
        guard let feature else { return ProStore.Feature.allCases }
        return [feature] + ProStore.Feature.allCases.filter { $0 != feature }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if store.isPro { alreadyPro } else { plans }
                    featureList
                    freeNote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.page)
            .safeAreaInset(edge: .bottom) { if !store.isPro { footer } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                await store.load()
                for p in store.products { trials[p.id] = await store.trialText(for: p) }
            }
            .onChange(of: store.isPro) { _, pro in if pro { dismiss() } }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("BrandIcon").resizable().frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            Text("Sortd Pro").font(.system(.largeTitle, weight: .bold)).padding(.top, 2)
            BrandBar()
            Text(feature.map { "\($0.title) is part of Sortd Pro." } ?? subtitle)
                .font(.body).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.element) { i, f in
                if i > 0 { Divider().padding(.leading, 52) }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: f.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.brandPalette[i % 4])
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.subheadline.weight(.semibold))
                        Text(f.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .surface(radius: 16)
    }

    /// "Less than a coffee a month" was true of the yearly plan and not the
    /// monthly one, said as though it covered both. Quotes the real
    /// per-month figure instead, from whatever the App Store returns.
    private var subtitle: String {
        guard let perMonth = displayPlans.first(where: { $0.id == ProStore.ID.yearly })?.perMonth else {
            return "Everything Sortd can do."
        }
        return "Everything Sortd can do, from \(perMonth) a month on the yearly plan."
    }

    private var displayPlans: [PlanDisplay] {
        #if DEBUG
        if store.products.isEmpty, ProcessInfo.processInfo.environment["SPEND_PAYWALL_DEMO"] == "1" {
            return [PlanDisplay(id: ProStore.ID.yearly, price: "$49.99", perMonth: "$4.17", trial: "14 days free", product: nil),
                    PlanDisplay(id: ProStore.ID.monthly, price: "$6.99", perMonth: nil, trial: nil, product: nil),
                    PlanDisplay(id: ProStore.ID.lifetime, price: "$99.99", perMonth: nil, trial: nil, product: nil)]
        }
        #endif
        return store.products.map { p in
            PlanDisplay(id: p.id, price: p.displayPrice,
                        perMonth: p.id == ProStore.ID.yearly ? monthly(of: p) : nil,
                        trial: trials[p.id], product: p)
        }
    }

    @ViewBuilder private var plans: some View {
        if displayPlans.isEmpty {
            HStack(spacing: 10) {
                if store.isLoading { ProgressView() }
                Text(store.loadError ?? "Loading plans…").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if store.loadError != nil {
                    Button("Retry") { Task { await store.load() } }.font(.subheadline.weight(.semibold))
                }
            }
            .padding(16).surface(radius: 16)
        } else {
            VStack(spacing: 10) {
                ForEach(displayPlans) { p in planRow(p) }
            }
        }
    }

    private func planRow(_ p: PlanDisplay) -> some View {
        let on = selected == p.id
        return Button { selected = p.id } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Color.ink : Color.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(p)).font(.body.weight(.semibold))
                        if p.id == ProStore.ID.yearly {
                            Text("Best value").font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.brandPalette[3].opacity(0.18), in: .capsule)
                                .foregroundStyle(Color.brandPalette[3])
                        }
                    }
                    Text(subtitle(p)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(p.price).font(.body.weight(.semibold)).monospacedDigit()
            }
            .padding(14)
            .background(Color.card, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? Color.ink : Color.secondary.opacity(0.2), lineWidth: on ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func title(_ p: PlanDisplay) -> String {
        switch p.id {
        case ProStore.ID.yearly: "Yearly"
        case ProStore.ID.monthly: "Monthly"
        default: "Lifetime"
        }
    }

    private func subtitle(_ p: PlanDisplay) -> String {
        if p.id == ProStore.ID.lifetime { return "Pay once. Yours for good." }
        var parts: [String] = []
        if let t = p.trial { parts.append(t) }
        if let perMonth = p.perMonth { parts.append("\(perMonth) a month") }
        if p.id == ProStore.ID.monthly { parts.append("Cancel any time") }
        return parts.joined(separator: " · ")
    }

    private func monthly(of p: Product) -> String? {
        let value = p.price / 12
        return value.formatted(p.priceFormatStyle)
    }

    private var alreadyPro: some View {
        Label("You have Sortd Pro. Thank you.", systemImage: "checkmark.seal.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.up)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 16)
    }

    private var freeNote: some View {
        Text("Free forever: Apple Pay logging, adding by hand, cards, export and delete.")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private var footer: some View {
        let plan = displayPlans.first { $0.id == selected }
        let product = plan?.product
        let trial = plan?.trial
        return VStack(spacing: 10) {
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button {
                guard let product else { message = "Plans are still loading from the App Store."; return }
                Task { await buy(product) }
            } label: {
                ZStack {
                    if working { ProgressView().tint(Color.onBrand) }
                    else { Text(cta(plan, trial: trial)) }
                }
                .primaryPill(enabled: plan != nil)
            }
            .buttonStyle(.plain)
            .disabled(plan == nil || working)

            Text(terms(plan, trial: trial))
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await restore() } }
                Button("Terms") { openURL(URL(string: "https://sortd.page/terms")!) }
                Button("Privacy") { openURL(URL(string: "https://sortd.page/privacy")!) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Color.page)
    }

    private func cta(_ p: PlanDisplay?, trial: String?) -> String {
        guard let p else { return "Continue" }
        if p.id == ProStore.ID.lifetime { return "Buy for \(p.price)" }
        if let trial {
            let length = trial.replacingOccurrences(of: " free", with: "")
                .replacingOccurrences(of: " days", with: "-day").replacingOccurrences(of: " week", with: "-week")
                .replacingOccurrences(of: " month", with: "-month")
            return "Start \(length) free trial"
        }
        return "Subscribe for \(p.price)"
    }

    /// Apple's renewal disclosure, in plain words.
    private func terms(_ p: PlanDisplay?, trial: String?) -> String {
        guard let p else { return "" }
        if p.id == ProStore.ID.lifetime { return "One payment of \(p.price). No subscription." }
        let period = p.id == ProStore.ID.yearly ? "year" : "month"
        let start = trial.map { "\($0), then " } ?? ""
        return "\(start)\(p.price) a \(period). Renews automatically until you cancel in Settings › Apple Account › Subscriptions, at least 24 hours before it renews."
    }

    private func buy(_ p: Product) async {
        working = true; message = nil
        defer { working = false }
        do {
            switch try await store.buy(p) {
            case .purchased: dismiss()
            case .pending: message = "Waiting for approval (for example Ask to Buy). Pro unlocks as soon as it's approved."
            case .cancelled: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        working = true; message = nil
        defer { working = false }
        do {
            try await store.restore()
            message = store.isPro ? nil : "No purchases found for this Apple Account."
        } catch {
            message = "Couldn't restore right now. Please try again."
        }
    }
}

/// A locked screen for Pro-only tabs and pages.
struct ProLockedView: View {
    let feature: ProStore.Feature
    @State private var showing = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: feature.symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(feature.title).font(.title2.weight(.bold))
            Text(feature.detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showing = true } label: { Text("Unlock with Sortd Pro").primaryPill() }
                .buttonStyle(.plain)
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.page)
        .sheet(isPresented: $showing) { PaywallView(feature: feature) }
    }
}

/// Shows the content with Sortd Pro, or the locked screen without it.
struct ProGate<Content: View>: View {
    let feature: ProStore.Feature
    @ViewBuilder var content: () -> Content
    @State private var store = ProStore.shared

    var body: some View {
        if store.isPro { content() } else { ProLockedView(feature: feature) }
    }
}
