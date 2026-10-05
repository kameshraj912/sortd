import SwiftUI

/// Picture-by-picture guide to the ready-made shortcut in Shortcuts. Each
/// page is a drawn copy of a real Shortcuts screen (checked on iOS 27.0, 27
/// Sep 2026) with the thing to tap ringed, so nothing depends on reading.
struct WalletSetupGuide: View {
    /// Two ways to get there. `quick` matches the ready-made shortcut at
    /// `sortd.page/apple-pay.shortcut`, which now carries the whole
    /// automation already built (the Wallet trigger and Sortd's action, both
    /// filled in) — so its three pages are just the three steps on
    /// `ApplePaySetupPanel`, drawn. `byHand` builds the whole thing from
    /// nothing, for anyone the download doesn't work for. `automation` and
    /// `automationByHand` are the two iOS 26 walk-throughs
    /// (`ApplePaySetupSteps.automationSteps` / `.byHandAutomationSteps`),
    /// drawn from the iOS 26.5 Shortcuts screens (5 Oct 2026); their pages
    /// are shown by `ApplePayAutomationGuide`, not by this pager.
    enum Route { case quick, byHand, automation, automationByHand }

    var route: Route = .quick

    #if DEBUG
    @State private var page = Int(ProcessInfo.processInfo.environment["SPEND_GUIDE_PAGE"] ?? "") ?? 0
    #else
    @State private var page = 0
    #endif

    struct Page: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    /// The three steps on `ApplePaySetupPanel`, drawn — same title and
    /// detail, so nothing is taught twice.
    static let quickPages: [Page] = [
        Page(id: 0, title: "Add the shortcut",
             detail: "Opens Shortcuts. Tap Add Shortcut."),
        Page(id: 1, title: ApplePaySetupSteps.runStep.title, detail: ApplePaySetupSteps.runStep.detail),
        Page(id: 2, title: ApplePaySetupSteps.automationStep(notificationTrigger: true).title,
             detail: ApplePaySetupSteps.automationStep(notificationTrigger: true).detail),
    ]

    /// The long way, for anyone who would rather not install a shortcut.
    static let byHandPages: [Page] = [
        Page(id: 0, title: "Open Shortcuts, tap + then Edit",
             detail: "+ is at the bottom. On the next screen tap Edit at the top right."),
        Page(id: 1, title: "Add the Wallet trigger",
             detail: "Tap the blue Automation chip first, type wallet, then tap Wallet."),
        Page(id: 2, title: "Add Log Wallet Tap",
             detail: "Type Sortd in the search box at the bottom and tap Log Wallet Tap."),
        Page(id: 3, title: "Fill Amount from the tap",
             detail: "Tap Amount, then Select Variable, then Shortcut Input. Now tap that blue word again and choose Amount."),
        Page(id: 4, title: "Do the same for Shop and Card",
             detail: "Shop → Shortcut Input → Merchant. Tap › for Card → Shortcut Input → Card or Pass."),
        Page(id: 5, title: "Go back. You're done.",
             detail: "It saves by itself. Now pay with Apple Pay in a shop. The ▶ button only runs a test."),
    ]

    /// An iOS 26 walk-through as pager pages, for the DEBUG screen host.
    static func pages(for steps: [ApplePaySetupSteps.AutomationStep]) -> [Page] {
        steps.map { Page(id: $0.id, title: $0.title, detail: $0.taps.joined(separator: " ")) }
    }

    var pages: [Page] {
        switch route {
        case .quick: Self.quickPages
        case .byHand: Self.byHandPages
        case .automation: Self.pages(for: ApplePaySetupSteps.automationSteps)
        case .automationByHand: Self.pages(for: ApplePaySetupSteps.byHandAutomationSteps)
        }
    }

    /// Kept so old call sites and tests still read the long route.
    static let pages: [Page] = byHandPages

    /// The drawn Shortcuts screen grows with Dynamic Type so its text never clips.
    @ScaledMetric(relativeTo: .subheadline) private var mockHeight: CGFloat = 220

    /// The pager scrolls by id; `page` stays a plain Int for the dots and chevrons.
    private var scrolledPage: Binding<Int?> {
        Binding(get: { page }, set: { if let new = $0 { page = new } })
    }

    var body: some View {
        VStack(spacing: 4) {
            // A paging scroll view instead of a page-style TabView: it takes the
            // height of its tallest page, so nothing clips at large text sizes
            // and no empty band is left on bigger phones.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(pages) { p in
                        pageView(p)
                            .containerRelativeFrame(.horizontal, alignment: .topLeading)
                            .id(p.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrolledPage)
            .scrollIndicators(.hidden)

            HStack {
                Button { withAnimation { page -= 1 } } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(page == 0)
                .accessibilityLabel("Previous step")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(pages) { p in
                        Capsule()
                            .fill(p.id == page ? Color.brandPalette[p.id % 4] : Color.secondary.opacity(0.3))
                            .frame(width: p.id == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
                Button { withAnimation { page += 1 } } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(page == pages.count - 1)
                .accessibilityLabel("Next step")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
            .buttonStyle(.pressable)
        }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortcutsMock(step: p.id, route: route)
                .frame(height: mockHeight)
                .accessibilityHidden(true)
            // No numbered badge here: the page dots below already show
            // position, and a second "1" inside a caller's own numbered
            // step read as a second step 1 (router feel check, 26 Sep 2026).
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.headline)
                Text(p.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(p.id + 1) of \(pages.count). \(p.title). \(p.detail)")
        }
    }
}

/// A small drawn Shortcuts screen for one step. Uses system colours so it
/// looks right in light and dark mode.
struct ShortcutsMock: View {
    let step: Int
    var route: WalletSetupGuide.Route = .byHand

    private static let blue = Color(red: 0.0, green: 0.48, blue: 1.0)
    private let ring = Color.brandPalette[0]

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            content
                .padding(14)
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .quick:
            switch step {
            case 0: addShortcutSheet
            case 1: allowPrompt
            default: automationSwitch
            }
        case .byHand:
            switch step {
            case 0: library
            case 1: triggerSearch
            case 2: actionSearch
            case 3: fieldTap
            case 4: pickVariable
            default: finished
            }
        case .automation:
            switch step {
            case 0: walletSearch
            case 1: cardsAndRun
            default: pickShortcut
            }
        case .automationByHand:
            switch step {
            case 0: walletSearch
            case 1: cardsAndRun
            case 2: createAndPick
            case 3: threeBoxes
            default: showWhenRunOff
            }
        }
    }

    // MARK: iOS 26 routes (the personal automation)

    /// (3, short way) The list after Next: the downloaded shortcut sits
    /// under "My Shortcuts".
    private var pickShortcut: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(icon: "plus.square.on.square", iconColor: Self.blue, title: "Create New Shortcut", subtitle: nil)
                .opacity(0.45)
            Text("My Shortcuts")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .tapRing(ring, label: "1")
                .padding(.top, 4)
            row(brand: true, title: "Log Apple Pay in Sortd", subtitle: nil)
                .tapRing(ring, label: "2")
            Spacer(minLength: 0)
        }
    }

    /// (1) The "new automation" list, with Wallet searched for.
    private var walletSearch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal Automation").font(.headline)
            row(icon: "creditcard.fill", iconColor: Self.blue, title: "Wallet",
                subtitle: "\u{201C}When I tap a Wallet Card or Pass\u{201D}")
                .tapRing(ring, label: "2")
            Spacer(minLength: 0)
            searchBar { Text("Wallet").font(.subheadline) }
                .tapRing(ring, label: "1")
        }
    }

    /// (2) "When I tap": the person's own cards, Run Immediately, Next.
    private var cardsAndRun: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("When I tap").font(.headline)
                Spacer()
                pill("Next", filled: true).tapRing(ring, label: "3")
            }
            VStack(spacing: 0) {
                checkRow("Your debit card", checked: true)
                Divider().padding(.leading, 12)
                checkRow("Your credit card", checked: true)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
            .tapRing(ring, label: "1")
            VStack(spacing: 0) {
                checkRow("Run After Confirmation", checked: false)
                Divider().padding(.leading, 12)
                checkRow("Run Immediately", checked: true)
                    .tapRing(ring, label: "2")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
        }
    }

    /// (3) Create New Shortcut, then Sortd in the list of apps, then its action.
    private var createAndPick: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(icon: "plus.square.on.square", iconColor: Self.blue, title: "Create New Shortcut", subtitle: nil)
                .tapRing(ring, label: "1")
            row(brand: true, title: "Sortd", subtitle: nil)
                .tapRing(ring, label: "2")
            row(brand: true, title: "Log Wallet Tap", subtitle: "Spending")
                .tapRing(ring, label: "3")
            Spacer(minLength: 0)
        }
    }

    /// (4) Sortd's action with its three boxes filled from the tap.
    private var threeBoxes: some View {
        VStack(alignment: .leading, spacing: 10) {
            card {
                Text("Log").font(.subheadline)
                token("Amount", symbol: "square.stack.3d.down.right").tapRing(ring, label: "1")
                Text("at").font(.subheadline)
                token("Merchant", symbol: "square.stack.3d.down.right").tapRing(ring, label: "2")
                Image(systemName: "chevron.right.circle.fill").foregroundStyle(Self.blue)
            }
            card {
                Text("Card").font(.subheadline)
                Spacer(minLength: 0)
                token("Card or Pass", symbol: "square.stack.3d.down.right").tapRing(ring, label: "3")
            }
            Spacer(minLength: 0)
            // What appears above the keyboard once a box is tapped.
            token("Shortcut Input", symbol: "square.stack.3d.down.right")
                .frame(maxWidth: .infinity)
        }
    }

    /// (5) Show When Run switched off, then Done.
    private var showWhenRunOff: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                pill("Done", filled: true).tapRing(ring, label: "2")
            }
            card {
                Text("Log").font(.subheadline)
                token("Amount", symbol: "square.stack.3d.down.right")
                Text("at").font(.subheadline)
                token("Merchant", symbol: "square.stack.3d.down.right")
            }
            card {
                Text("Show When Run").font(.subheadline)
                Spacer(minLength: 0)
                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 44, height: 26)
                    .overlay(alignment: .leading) {
                        Circle().fill(.white).padding(2)
                    }
                    .tapRing(ring, label: "1")
            }
            Spacer(minLength: 0)
        }
    }

    /// A list row with a tick at the end when chosen.
    private func checkRow(_ text: String, checked: Bool) -> some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.blue)
                .opacity(checked ? 1 : 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    // MARK: Quick route (the ready-made shortcut, checked on iOS 27)

    /// (a) The Add Shortcut sheet that Safari opens for the download: the
    /// shortcut's own card, and the blue Add Shortcut button.
    private var addShortcutSheet: some View {
        VStack(spacing: 10) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 5)
            row(brand: true, title: "Log Apple Pay in Sortd", subtitle: "Shortcut")
            Spacer(minLength: 0)
            pill("Add Shortcut", filled: true).tapRing(ring, label: nil)
        }
    }

    /// (b) The shortcut open in the library, with iOS's own permission
    /// prompt over it — the one that's lost if the first run isn't done by
    /// hand. Don't Allow on the left, Allow (ringed) on the right.
    private var allowPrompt: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                trigger
                // Sortd's own action, as the imported shortcut shows it
                // (there is no Run Shortcut step any more).
                card {
                    Text("Log").font(.subheadline)
                    token("Amount", symbol: "square.stack.3d.down.right")
                    Text("at").font(.subheadline)
                    token("Merchant", symbol: "square.stack.3d.down.right")
                }
                Spacer(minLength: 0)
            }
            .opacity(0.35)

            VStack(spacing: 0) {
                Text("Allow “Log Apple Pay in Sortd” to run actions from “Sortd”?")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                Divider()
                HStack(spacing: 0) {
                    Text("Don't Allow").font(.subheadline).frame(maxWidth: .infinity)
                    Divider().frame(height: 30)
                    Text("Allow").font(.subheadline.weight(.semibold)).foregroundStyle(Self.blue)
                        .frame(maxWidth: .infinity)
                        .tapRing(ring, label: nil)
                }
                .padding(.vertical, 10)
            }
            .frame(maxWidth: 230)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    /// (c) Both "When…" cards the shortcut carries since 2 Oct 2026 — the
    /// tap at a till and Wallet's notification (apps and websites) — each
    /// with its own Automation switch on (ringed, numbered in turn).
    private var automationSwitch: some View {
        VStack(alignment: .leading, spacing: 10) {
            switchCard(trigger: trigger, order: "1")
            switchCard(trigger: notificationTrigger, order: "2")
            Spacer(minLength: 0)
        }
    }

    /// A "When…" card with its Automation switch on.
    private func switchCard(trigger: some View, order: String) -> some View {
        VStack(spacing: 0) {
            trigger
            Divider().padding(.leading, 12)
            HStack {
                Text("Automation").font(.subheadline)
                Spacer(minLength: 0)
                Capsule().fill(Self.blue).frame(width: 44, height: 26)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).padding(2)
                    }
                    .tapRing(ring, label: order)
            }
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// The second "When…" line: Wallet's notification (iOS 27).
    private var notificationTrigger: some View {
        card {
            Image(systemName: "app.badge.fill").foregroundStyle(Self.blue)
            Text("When").font(.subheadline)
            Text("Wallet").font(.subheadline).foregroundStyle(Self.blue)
            Text("sends a notification").font(.subheadline)
        }
    }

    // MARK: Screens

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                pill("Edit").tapRing(ring, label: "2")
            }
            Text("All Shortcuts").font(.title3.weight(.bold))
            HStack(spacing: 8) {
                tile(Color.purple.opacity(0.8))
                tile(Color.pink.opacity(0.8))
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .circle)
                    .tapRing(ring, label: "1", circle: true)
                Spacer()
            }
        }
    }

    private var triggerSearch: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchBar {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.checkmark")
                    Text("Automation")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.secondary, in: .rect(cornerRadius: 5))
                Text("wallet").font(.subheadline)
            }
            HStack(spacing: 6) {
                chip("Automation", "clock.badge.checkmark").tapRing(ring, label: "1")
                chip("Scripting", "curlybraces")
            }
            row(icon: "creditcard.fill", iconColor: Self.blue, title: "Wallet",
                subtitle: "“When I tap a Wallet Card or Pass”")
                .tapRing(ring, label: "2")
            Spacer(minLength: 0)
        }
    }

    private var actionSearch: some View {
        VStack(alignment: .leading, spacing: 10) {
            trigger
            Spacer(minLength: 0)
            searchBar { Text("Sortd").font(.subheadline) }
            row(brand: true, title: "Log Wallet Tap", subtitle: nil)
                .tapRing(ring, label: nil)
        }
    }

    private var fieldTap: some View {
        VStack(alignment: .leading, spacing: 10) {
            trigger
            action(filled: false)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Text("Select Variable")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .tapRing(ring, label: "2")
                Divider().frame(height: 20)
                Label("Ask Each Time", systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
        }
    }

    private var pickVariable: some View {
        VStack(spacing: 8) {
            Text("Select Variable").font(.footnote.weight(.semibold))
            token("Shortcut Input", symbol: "square.stack.3d.down.right").opacity(0.5)
            trigger
            token("Transaction", symbol: "creditcard")
                .tapRing(ring, label: nil)
            action(filled: false).opacity(0.5)
            Spacer(minLength: 0)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .circle)
                    .tapRing(ring, label: nil, circle: true)
                Spacer()
            }
            trigger
            action(filled: true)
            Spacer(minLength: 0)
            Label("Ready. Pay with Apple Pay to log.", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.up)
        }
    }

    // MARK: Pieces

    private var trigger: some View {
        card {
            Image(systemName: "creditcard.fill").foregroundStyle(Self.blue)
            Text("When").font(.subheadline)
            Text("Any Card").font(.subheadline).foregroundStyle(Self.blue)
            Text("is tapped").font(.subheadline)
        }
    }

    private func action(filled: Bool) -> some View {
        card {
            brandIcon
            Text("Log").font(.subheadline)
            if filled {
                token("Transaction", symbol: "creditcard")
            } else {
                Text("Transaction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 6))
                    .tapRing(step == 3 ? ring : .clear, label: step == 3 ? "1" : nil)
            }
            Text("in Sortd").font(.subheadline)
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) { c() }
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func token(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Self.blue)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Self.blue.opacity(0.14), in: .rect(cornerRadius: 6))
            .lineLimit(1)
            .fixedSize()
    }

    private func searchBar<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            c()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.14), in: .capsule)
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(Self.blue)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
    }

    private func row(icon: String = "", iconColor: Color = .clear, brand: Bool = false,
                     title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            if brand { brandIcon } else { Image(systemName: icon).foregroundStyle(iconColor) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// `filled` draws the blue, white-text button shape (Add Shortcut);
    /// plain stays the grey chip (Edit).
    private func pill(_ text: String, filled: Bool = false) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(filled ? .white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(filled ? Self.blue : Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
    }

    private func tile(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.gradient)
            .frame(height: 54)
    }

    private var brandIcon: some View {
        Image("BrandIcon").resizable().frame(width: 20, height: 20)
            .clipShape(.rect(cornerRadius: 5, style: .continuous))
    }
}

private extension View {
    /// Rings the thing to tap, with an optional order number.
    func tapRing(_ color: Color, label: String?, circle: Bool = false) -> some View {
        overlay {
            Group {
                if circle { Circle().strokeBorder(color, lineWidth: 2.5) }
                else { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color, lineWidth: 2.5) }
            }
            .padding(-3)
        }
        .overlay(alignment: .topTrailing) {
            if let label {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(color, in: .circle)
                    .offset(x: 9, y: -9)
            }
        }
    }
}
