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
    /// nothing, for anyone the download doesn't work for.
    enum Route { case quick, byHand }

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
        Page(id: 1, title: "Run it once and tap Allow",
             detail: "Press ▶ in the shortcut. Sortd says it's connected."),
        Page(id: 2, title: "Turn the automation on",
             detail: "Tap › next to “tapped”, then switch on Automation."),
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

    var pages: [Page] { route == .quick ? Self.quickPages : Self.byHandPages }

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
            .buttonStyle(.plain)
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
        if route == .quick {
            switch step {
            case 0: addShortcutSheet
            case 1: allowPrompt
            default: automationSwitch
            }
        } else {
            switch step {
            case 0: library
            case 1: triggerSearch
            case 2: actionSearch
            case 3: fieldTap
            case 4: pickVariable
            default: finished
            }
        }
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

    /// (c) The trigger card expanded: Categories and Merchants left as the
    /// shortcut ships them, Automation switched on (ringed).
    private var automationSwitch: some View {
        VStack(alignment: .leading, spacing: 0) {
            trigger
            VStack(spacing: 0) {
                pickRow("Categories", value: "Food & Drink and 5 more")
                Divider().padding(.leading, 12)
                pickRow("Merchants", value: "Any Merchant")
                Divider().padding(.leading, 12)
                HStack {
                    Text("Automation").font(.subheadline)
                    Spacer(minLength: 0)
                    Capsule().fill(Self.blue).frame(width: 44, height: 26)
                        .overlay(alignment: .trailing) {
                            Circle().fill(.white).padding(2)
                        }
                }
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .tapRing(ring, label: nil)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
        }
    }

    /// A settings row: a label on the left, its value on the right, and an
    /// optional checkmark for the by-hand route's own choices.
    private func pickRow(_ title: String, value: String? = nil, chosen: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline)
            Spacer(minLength: 0)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(.secondary)
            }
            if chosen {
                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Self.blue)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 10)
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
