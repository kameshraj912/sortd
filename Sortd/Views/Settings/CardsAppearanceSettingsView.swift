import SwiftUI

/// Settings › Cards & Appearance: the cards Sortd knows about, light/dark
/// mode, the card gradient style, and the widgets guide.
struct CardsAppearanceSettingsView: View {
    @AppStorage("cardStyle") private var cardStyle = SpendGradient.Style.satin.rawValue
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        List {
            ListPageTitle(title: "Cards & Appearance")
            Section {
                NavigationLink {
                    CardsSettingsView()
                } label: {
                    LabeledContent {
                        Text("\(Card.mine.count)")
                    } label: {
                        Label("Cards", systemImage: "creditcard")
                    }
                }
                Picker(selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .onChange(of: appearance) { _, value in Appearance.apply(value) }
                NavigationLink {
                    CardStyleView()
                } label: {
                    LabeledContent {
                        Text(SpendGradient.Style(rawValue: cardStyle)?.name ?? "Satin")
                    } label: {
                        Label("Card Style", systemImage: "paintpalette")
                    }
                }
                NavigationLink {
                    WidgetsGuideView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Widgets")
                            Text("Home and Lock Screen · light or dark")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            } footer: {
                Text("Cards are coloured by what you spend on them.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Cards & Appearance")
    }
}
