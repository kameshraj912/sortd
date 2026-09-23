import SwiftUI
import SwiftData

/// Settings › Currency: what totals are shown in, the currency purchases are
/// detected in, and refreshing the on-device exchange rates.
struct CurrencySettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @State private var refreshing = false

    var body: some View {
        List {
            ListPageTitle(title: "Currency")
            Section {
                Picker("Show Totals In", selection: $home) {
                    ForEach(Money.supported, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
                .onChange(of: home) { _, new in
                    Task {
                        refreshing = true
                        await FXService.rebase(to: new, in: context)
                        refreshing = false
                    }
                }
                LabeledContent("Local Currency", value: "\(LocalCurrency.current()), from your time zone")
                Button {
                    Task {
                        refreshing = true
                        await FXService.backfill(in: context)
                        refreshing = false
                    }
                } label: {
                    HStack {
                        Text("Update Exchange Rates")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing)
            } footer: {
                Text("Purchases in other currencies are converted to \(home) at that day's European Central Bank rate.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Currency")
    }
}
