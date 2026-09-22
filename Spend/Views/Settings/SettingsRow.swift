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

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}
