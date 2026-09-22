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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings rows are a size down from a plain List: subheadline text and a
/// ~20pt symbol in a fixed ~24pt column, so the screen reads as a quiet
/// list of options rather than big body text. Both scale with Dynamic Type.
struct SettingsLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var symbolSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .font(.subheadline)
        } icon: {
            configuration.icon
                .font(.system(size: symbolSize))
                .frame(width: column, height: column)
        }
        // The system style, so List still lines the separator up with the
        // title. Without it this style would call itself.
        .labelStyle(.titleAndIcon)
    }
}

/// The List every Settings page uses, so they all match: subheadline row
/// text (from `SettingsLabelStyle`; rows that aren't a Label set it
/// themselves), smaller symbols, and rows 8pt above and below. Not a
/// List-wide font: that would also enlarge the section footers. Row insets
/// only reach rows through a container inside the List — hence the Group.
struct SettingsList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowInsets(.vertical, 8)
        }
        .labelStyle(SettingsLabelStyle())
        .environment(\.defaultMinListRowHeight, 36)
    }
}
