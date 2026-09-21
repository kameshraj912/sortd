import SwiftUI
import SwiftData

/// The colour of a card, made from what it was spent on (Apple Card idea):
/// each of the top categories becomes a soft patch of its colour, sized by
/// its share of the spend. Three looks; Raj picks one in Settings.
struct SpendGradient: View {
    enum Style: String, CaseIterable, Identifiable {
        /// Smooth even blend with fine grain, calm and flat.
        case satin
        /// Bright and airy, colours glow on a light base (closest to Apple Card).
        case glow
        /// Black card; spending shows as a thin bar down the side.
        case mono
        /// Light card; spending shows as a thin bar along the bottom.
        case minimal
        // Plain finishes: the card doesn't change with spending.
        /// Dark brushed metal (like a titanium or metal card).
        case graphite
        /// Light brushed silver.
        case silver
        /// Deep navy with a soft sheen.
        case midnight
        /// Warm matte sand.
        case sand

        var id: String { rawValue }
        var name: String {
            switch self {
            case .satin: "Satin"
            case .glow: "Glow"
            case .mono: "Mono"
            case .minimal: "Minimal"
            case .graphite: "Graphite"
            case .silver: "Silver"
            case .midnight: "Midnight"
            case .sand: "Sand"
            }
        }

        /// Needs dark text (light card face).
        var lightFace: Bool { self == .silver || self == .sand }

        /// Uses the normal text colour (Minimal sits on the card background,
        /// light or dark with the system).
        var systemFace: Bool { self == .minimal }

        /// Plain finishes ignore spending, so they look the same for every card.
        var isPlain: Bool { [.graphite, .silver, .midnight, .sand].contains(self) }
    }

    let shares: [Share]
    var style: Style = .glow
    @Environment(\.colorScheme) private var scheme

    init(transactions: [Transaction], style: Style = .glow) {
        self.shares = Self.shares(transactions)
        self.style = style
    }

    /// For previews: category shares directly.
    init(shares: [Share], style: Style) {
        self.shares = shares
        self.style = style
    }

    var body: some View {
        if style.isPlain {
            GeometryReader { geo in plain(geo.size) }
        } else if shares.isEmpty {
            LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(scheme == .dark ? 0.6 : 1)
        } else {
            GeometryReader { geo in
                switch style {
                case .glow: glow(shares, geo.size)
                case .satin: satin(shares)
                case .mono: mono(shares, geo.size)
                case .minimal: minimal(shares, geo.size)
                default: plain(geo.size)
                }
            }
            // Dark Mode: a big bright card would glow against black (Apple
            // HIG: soften bright areas), so dim it a little.
            .overlay(Color.black.opacity(scheme == .dark && !style.lightFace && style != .mono ? 0.18 : 0))
        }
    }

    // MARK: Looks

    /// Big blurred patches of colour over a pale tint of the top category.
    private func glow(_ shares: [Share], _ size: CGSize) -> some View {
        ZStack {
            shares[0].color.mix(with: .white, by: 0.35)
            blobs(shares, size, scale: 1.25, lift: 0.1)
                .blur(radius: size.width * 0.14)
            RadialGradient(colors: [.white.opacity(0.45), .clear], center: .topLeading,
                           startRadius: 0, endRadius: size.width * 0.8)
                .blendMode(.softLight)
            LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .center, endPoint: .bottom)
            Grain(opacity: 0.05)
        }
    }

    /// Straight diagonal blend through the colours in order of spend.
    private func satin(_ shares: [Share]) -> some View {
        var stops: [Gradient.Stop] = []
        var at = 0.0
        for s in shares {
            stops.append(.init(color: s.color.mix(with: .white, by: 0.08), location: at + s.fraction / 2))
            at += s.fraction
        }
        if stops.count == 1 {
            stops = [.init(color: shares[0].color.mix(with: .white, by: 0.25), location: 0),
                     .init(color: shares[0].color.mix(with: .black, by: 0.15), location: 1)]
        }
        return ZStack {
            LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.10)],
                           startPoint: .top, endPoint: .bottom)
            Grain(opacity: 0.06)
        }
    }

    private func mono(_ shares: [Share], _ size: CGSize) -> some View {
        ZStack(alignment: .trailing) {
            Color(red: 0.08, green: 0.08, blue: 0.09)
            VStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, s in
                    s.color.frame(height: max(4, (size.height - 24) * s.fraction))
                }
            }
            .frame(width: 5)
            .clipShape(.capsule)
            .padding(.vertical, 12)
            .padding(.trailing, 7)
            Grain(opacity: 0.06)
        }
    }

    private func minimal(_ shares: [Share], _ size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Color.card
            HStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.offset) { _, s in
                    s.color.frame(width: size.width * s.fraction)
                }
            }
            .frame(height: 6)
        }
    }

    /// Plain finishes: a base colour, a soft diagonal sheen and fine
    /// "brushed" lines, the way metal and matte cards read in photos.
    private func plain(_ size: CGSize) -> some View {
        let (top, bottom): (Color, Color) = switch style {
        case .silver: (Color(red: 0.90, green: 0.90, blue: 0.91), Color(red: 0.76, green: 0.77, blue: 0.79))
        case .midnight: (Color(red: 0.12, green: 0.16, blue: 0.27), Color(red: 0.05, green: 0.07, blue: 0.13))
        case .sand: (Color(red: 0.91, green: 0.87, blue: 0.80), Color(red: 0.82, green: 0.76, blue: 0.67))
        default: (Color(red: 0.25, green: 0.25, blue: 0.27), Color(red: 0.10, green: 0.10, blue: 0.11))
        }
        return ZStack {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Sheen across the card.
            LinearGradient(stops: [.init(color: .clear, location: 0.25),
                                   .init(color: .white.opacity(style == .sand ? 0.10 : 0.16), location: 0.45),
                                   .init(color: .clear, location: 0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if style == .graphite || style == .silver { Brushed() }
            Grain(opacity: style == .sand ? 0.08 : 0.04)
        }
    }

    /// One circle per category. Bigger share, bigger circle. Placed at fixed
    /// spots so a card looks the same every time you open it.
    private func blobs(_ shares: [Share], _ size: CGSize, scale: Double, lift: Double, anchorBottom: Bool = false) -> some View {
        let spots: [UnitPoint] = anchorBottom
            ? [.init(x: 0.15, y: 1.0), .init(x: 0.9, y: 0.95), .init(x: 0.55, y: 0.75), .init(x: 0.95, y: 0.3)]
            : [.init(x: 0.2, y: 0.3), .init(x: 0.85, y: 0.75), .init(x: 0.75, y: 0.15), .init(x: 0.25, y: 0.95)]
        return ZStack {
            // Smallest drawn first so the biggest share stays on top and visible.
            ForEach(Array(shares.enumerated()).reversed(), id: \.offset) { i, s in
                let d = size.width * scale * (0.45 + 0.75 * sqrt(s.fraction))
                Circle()
                    .fill(s.color.mix(with: .white, by: lift))
                    .frame(width: d, height: d)
                    .position(x: spots[i].x * size.width, y: spots[i].y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Data

    struct Share: Sendable {
        let color: Color
        let fraction: Double
    }

    /// Top 4 categories by spend, as fractions of their total.
    static func shares(_ transactions: [Transaction]) -> [Share] {
        let totals = Dictionary(grouping: transactions, by: \.category)
            .map { (category: $0.key, total: $0.value.audTotal.double) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(4)
        let sum = totals.reduce(0) { $0 + $1.total }
        guard sum > 0 else { return [] }
        return totals.map { Share(color: $0.category.color, fraction: $0.total / sum) }
    }
}

/// Fine horizontal lines, like brushed metal. Same pattern every draw.
private struct Brushed: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 11)
            var y: CGFloat = 0
            while y < size.height {
                let alpha = Double(rng.next() % 100) / 100 * 0.06
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                         with: .color(.white.opacity(alpha)))
                y += 1.5
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fine film grain so large gradients don't band. Same pattern every draw.
private struct Grain: View {
    let opacity: Double

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 7)
            let count = Int(size.width * size.height / 30)
            for _ in 0..<count {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let white = rng.next() % 2 == 0
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                         with: .color(white ? .white : .black))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#if DEBUG
/// Side-by-side comparison of the three looks on real data.
/// Launch with SPEND_GRADIENT_LAB=1.
struct GradientLab: View {
    @Environment(\.modelContext) private var context
    @State private var items: [Transaction] = []

    var body: some View {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = items.filter { $0.date >= start }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(SpendGradient.Style.allCases) { style in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(style.name).font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                WalletCard(card: nil, transactions: month, styleOverride: style).frame(width: 216)
                                ForEach([Card.scDebit, .stanchart, .nab, .cimb], id: \.self) { c in
                                    WalletCard(card: c, transactions: month.filter { $0.card == c }, styleOverride: style)
                                        .frame(width: 216)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding(20)
        }
        .background(Color.page)
        .task { items = (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }
    }
}
#endif

/// Settings › Card Style: every look side by side, on a sample spending mix.
struct CardStyleView: View {
    @AppStorage("cardStyle") private var styleRaw = SpendGradient.Style.satin.rawValue

    private let sample: [SpendGradient.Share] = [
        .init(color: SpendCategory.foodDelivery.color, fraction: 0.42),
        .init(color: SpendCategory.eatingOut.color, fraction: 0.26),
        .init(color: SpendCategory.subscriptions.color, fraction: 0.2),
        .init(color: SpendCategory.groceries.color, fraction: 0.12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Card Style")
                Text("Coloured styles follow what you spend by category. Plain styles stay the same.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                group("Coloured by spending", SpendGradient.Style.allCases.filter { !$0.isPlain })
                group("Plain", SpendGradient.Style.allCases.filter(\.isPlain))
            }
            .padding(20)
        }
        .background(Color.page)
        .brandedTitle("Card Style")
        .sensoryFeedback(.selection, trigger: styleRaw)
    }

    private func group(_ title: String, _ styles: [SpendGradient.Style]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.secondary).padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(styles) { style in
                    Button { styleRaw = style.rawValue } label: { tile(style) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(style.name)
                        .accessibilityAddTraits(styleRaw == style.rawValue ? .isSelected : [])
                }
            }
        }
    }

    private func tile(_ style: SpendGradient.Style) -> some View {
        let selected = styleRaw == style.rawValue
        return VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Everyday").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(Money.format(1284, Money.home, cents: false))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            .foregroundStyle(style.systemFace ? Color.primary : style.lightFace ? Color(white: 0.1) : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.586, contentMode: .fit)
            .background { SpendGradient(shares: sample, style: style) }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style.systemFace ? Color.hairline : .clear, lineWidth: 1)
            }
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(selected ? Color.ink : .clear, lineWidth: 2)
            }
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(style.name).font(.subheadline.weight(selected ? .semibold : .regular))
            }
        }
    }
}
