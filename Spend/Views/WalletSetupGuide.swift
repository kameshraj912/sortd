import SwiftUI

/// Picture-by-picture guide to the Wallet automation in Shortcuts. Each page
/// is a drawn copy of the real Shortcuts screen (checked on iOS 27.0, Sep
/// 2026) with the thing to tap ringed, so nothing depends on reading.
struct WalletSetupGuide: View {
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

    static let pages: [Page] = [
        Page(id: 0, title: "Open Shortcuts, tap + then Edit",
             detail: "+ is at the bottom. On the next screen tap Edit at the top right."),
        Page(id: 1, title: "Add the Wallet trigger",
             detail: "Tap the blue Automation chip first, type wallet, then tap Wallet."),
        Page(id: 2, title: "Add Log Wallet Tap",
             detail: "Type Sortd in the search box at the bottom and tap Log Wallet Tap."),
        Page(id: 3, title: "Tap Transaction, then Select Variable",
             detail: "Tap the grey word Transaction. Then tap Select Variable above the keyboard."),
        Page(id: 4, title: "Tap the blue Transaction",
             detail: "It's just under “When Any Card is tapped”. That's the only one you pick."),
        Page(id: 5, title: "Tap back. Done.",
             detail: "It saves by itself. Now pay with Apple Pay in a shop. The ▶ button only runs a test."),
    ]

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                ForEach(Self.pages) { p in
                    VStack(alignment: .leading, spacing: 12) {
                        ShortcutsMock(step: p.id)
                            .frame(height: 230)
                            .accessibilityHidden(true)
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(p.id + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.onBrand)
                                .frame(width: 26, height: 26)
                                .background(Color.ink, in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.subheadline.weight(.semibold))
                                Text(p.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(p.id + 1) of \(Self.pages.count). \(p.title). \(p.detail)")
                        Spacer(minLength: 0)
                    }
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 330)

            HStack {
                Button { withAnimation { page -= 1 } } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(page == 0)
                .accessibilityLabel("Previous step")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Self.pages) { p in
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
                .disabled(page == Self.pages.count - 1)
                .accessibilityLabel("Next step")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
            .buttonStyle(.plain)
        }
    }
}

/// A small drawn Shortcuts screen for one step. Uses system colours so it
/// looks right in light and dark mode.
struct ShortcutsMock: View {
    let step: Int

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
        switch step {
        case 0: library
        case 1: triggerSearch
        case 2: actionSearch
        case 3: fieldTap
        case 4: pickVariable
        default: finished
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

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
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
