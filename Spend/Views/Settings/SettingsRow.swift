import SwiftUI

/// Coloured rounded-square icon for a top-level Settings row, matching the
/// style iOS's own Settings app uses (a tinted SF Symbol on a solid colour
/// square) so the grouped list reads at a glance.
struct SettingsIconBadge: View {
    let symbol: String
    let tint: Color
    /// Grows with Dynamic Type, capped so rows stay usable at huge sizes.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = 29 * min(scale, 1.6)
        Image(systemName: symbol)
            .font(.system(size: side * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.gradient, in: .rect(cornerRadius: side * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A top-level Settings row that pushes to a sub-page: icon badge, title,
/// and an optional status subtitle underneath it.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            SettingsIconBadge(symbol: symbol, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}
