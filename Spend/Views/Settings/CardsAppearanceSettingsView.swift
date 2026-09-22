import SwiftUI

/// Settings › Cards & Appearance: the cards Sortd knows about, light/dark
/// mode, the card gradient style, and the widgets guide.
struct CardsAppearanceSettingsView: View {
    @AppStorage("cardStyle") private var cardStyle = SpendGradient.Style.satin.rawValue
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        SettingsList {
            ListPageTitle(title: "Cards & Appearance", subtitle: "Your cards, how they look, and where they show up.")
            Section {
                NavigationLink {
                    CardsSettingsView()
                } label: {
                    LabeledContent {
                        Text("\(Card.mine.count)")
                    } label: {
                        Label("Cards", systemImage: "creditcard")
                    }
                    .font(.subheadline)
                }
                Picker(selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .font(.subheadline)
                .onChange(of: appearance) { _, value in Appearance.apply(value) }
                NavigationLink {
                    CardStyleView()
                } label: {
                    LabeledContent {
                        Text(SpendGradient.Style(rawValue: cardStyle)?.name ?? "Satin")
                    } label: {
                        Label("Card Style", systemImage: "paintpalette")
                    }
                    .font(.subheadline)
                }
                NavigationLink {
                    WidgetsGuideView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Widgets")
                            Text("Home and Lock Screen · light or dark")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            } header: {
                BoldHeader("Cards")
            } footer: {
                Text("Cards are coloured by what you spend on them. Appearance follows your iPhone unless you pick Light or Dark.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Cards & Appearance")
    }
}
