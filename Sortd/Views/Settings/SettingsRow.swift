import SwiftUI

/// A top-level Settings row that pushes to a sub-page: a plain SF Symbol
/// (no coloured tile — Sortd keeps colour for spending categories, per
/// `Theme.swift`), a title, and an optional status subtitle underneath it.
/// Same shape as the single-line `Label` rows the rest of Settings already
/// uses (see "Widgets", "Apple Pay Auto-Logging").
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest text sizes the icon goes, so the title has the
        // whole row and words aren't broken in the middle ("Pur-chase").
        if typeSize.isAccessibilitySize {
            text.accessibilityElement(children: .combine)
        } else {
            Label { text } icon: { Image(systemName: symbol) }
                .accessibilityElement(children: .combine)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
