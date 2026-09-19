import SwiftUI

/// Simple and neutral, colourful only where it matters. Based on Raj's two
/// references: the "Budgeting Application" concept (big total, a budget card
/// with a colour-split bar) and Budgeta's plain dated list. Black and grey
/// for UI; colour is reserved for spending categories.
/// Flat: white cards with a hairline border, no shadows, gradients or glass.
/// Colour always means "where money went".
extension Color {
    nonisolated private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Neutral accent: near-black (#16161A) in light, near-white in dark.
    /// Buttons, selected chips/tabs and links use this, so the only colour
    /// on screen is category colour.
    /// Dark side is a soft off-white (#E8E8EA), not pure white: pure white
    /// on near-black "glows" and is tiring to read (halation).
    nonisolated static let brand = adaptive(
        light: UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1),
        dark: UIColor(red: 0.910, green: 0.910, blue: 0.918, alpha: 1))
    nonisolated static let onBrand = adaptive(light: .white, dark: .black)

    /// Headline text, same as the accent.
    nonisolated static let ink = brand

    /// Page background: off-white (#F7F7FA) / black.
    /// In Dark Mode this is the system grouped background, so sheets and
    /// pop-ups get the brighter "elevated" shade automatically (Apple HIG).
    /// Dark: a very dark grey (#121214), not pure black (Material's #121212
    /// advice); sheets and pop-ups sit one step lighter (#1C1C1F).
    nonisolated static let page = Color(UIColor { t in
        guard t.userInterfaceStyle == .dark else { return UIColor(red: 0.969, green: 0.969, blue: 0.980, alpha: 1) }
        return t.userInterfaceLevel == .elevated
            ? UIColor(red: 0.110, green: 0.110, blue: 0.122, alpha: 1)
            : UIColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
    })

    /// Card fill: white / #1C1C1E.
    /// Dark: cards are one clear step above the page (#1E1E21), and one
    /// more inside sheets (#29292D) — depth by lighter layers, not shadows.
    nonisolated static let card = Color(UIColor { t in
        guard t.userInterfaceStyle == .dark else { return .white }
        return t.userInterfaceLevel == .elevated
            ? UIColor(red: 0.161, green: 0.161, blue: 0.176, alpha: 1)
            : UIColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1)
    })

    /// Hairline card border.
    nonisolated static let hairline = Color(UIColor { t in
        let high = t.accessibilityContrast == .high
        return t.userInterfaceStyle == .dark
            ? UIColor(white: high ? 0.38 : 0.22, alpha: 1)
            : (high ? UIColor(white: 0.72, alpha: 1) : UIColor(red: 0.918, green: 0.918, blue: 0.945, alpha: 1))
    })

    /// Empty part of bars.
    nonisolated static let track = Color(UIColor { t in
        let high = t.accessibilityContrast == .high
        return t.userInterfaceStyle == .dark
            ? UIColor(white: high ? 0.34 : 0.22, alpha: 1)
            : UIColor(white: high ? 0.80 : 0.906, alpha: 1)
    })

    /// Filled look for credit cards and badges. Stays "the solid one" in both
    /// modes: near-black in light, raised grey in dark (white text on both).
    nonisolated static let creditFill = adaptive(
        light: UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1),
        dark: UIColor(white: 0.30, alpha: 1))

    /// Sortd's logo colours (the four sorted bars), in order. Used sparingly
    /// as accents on the black-and-white UI.
    nonisolated static let brandPalette: [Color] = [
        Color(red: 0.941, green: 0.392, blue: 0.239),   // #F0643D
        Color(red: 0.961, green: 0.651, blue: 0.137),   // #F5A623
        Color(red: 0.482, green: 0.420, blue: 0.941),   // #7B6BF0
        Color(red: 0.169, green: 0.690, blue: 0.478),   // #2BB07A
    ]

    nonisolated static let up = Color(red: 0.13, green: 0.63, blue: 0.42)
    nonisolated static let down = Color(red: 0.90, green: 0.28, blue: 0.30)
}

/// The four logo colours as short bars, like under the wordmark.
struct BrandBar: View {
    var width: CGFloat = 18
    var height: CGFloat = 4

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Color.brandPalette.indices, id: \.self) { i in
                Capsule().fill(Color.brandPalette[i]).frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// White rounded group, exactly like an iOS Settings section: no border,
/// no shadow. The one surface used everywhere.
struct Surface: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(Color.card, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

/// Pill chip: filled black when selected, outlined otherwise.
struct ChipStyle: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(selected ? Color.onBrand : Color.ink)
            .background(selected ? Color.brand : Color.clear, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: 1))
    }
}

/// Full-width primary button.
struct PrimaryPill: ViewModifier {
    var enabled = true

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(enabled ? Color.onBrand : Color.secondary)
            .background(enabled ? Color.brand : Color.track, in: .capsule)
    }
}

/// Horizontal bar split into coloured segments (e.g. spend per category),
/// with the unused part in grey. Segments are fractions of `total`.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let total: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    s.color.frame(width: max(0, geo.size.width * min(s.value, total) / max(total, 0.01) - 2))
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .background(Color.track)
            .clipShape(.capsule)
        }
        .frame(height: height)
    }
}

extension View {
    func surface(radius: CGFloat = 24) -> some View { modifier(Surface(radius: radius)) }
    func chip(selected: Bool) -> some View { modifier(ChipStyle(selected: selected)) }
    func primaryPill(enabled: Bool = true) -> some View { modifier(PrimaryPill(enabled: enabled)) }
}

/// List section heading in the setup style: bold, normal case, ink colour
/// (instead of iOS's small grey capitals).
struct BoldHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.ink)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Section where Parent == BoldHeader, Footer == EmptyView, Content: View {
    /// `Section(bold: "Details") { … }`
    init(bold title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { BoldHeader(title) })
    }
}
