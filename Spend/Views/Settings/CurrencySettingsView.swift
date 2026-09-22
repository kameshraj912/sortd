import SwiftUI
import SwiftData

/// Settings › Currency: what totals are shown in, the currency purchases are
/// detected in, and refreshing the on-device exchange rates.
struct CurrencySettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @State private var refreshing = false
    /// What the last update did, in one line.
    @State private var fxResult: String?

    var body: some View {
        SettingsList {
            ListPageTitle(title: "Currency", subtitle: "What Sortd totals in, and how it converts.")
            Section {
                Picker("Totals shown in", selection: $home) {
                    ForEach(Money.supported, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
                .font(.subheadline)
                .onChange(of: home) { _, new in
                    Task {
                        refreshing = true
                        fxResult = nil
                        await FXService.rebase(to: new, in: context)
                        refreshing = false
                    }
                }
                LabeledContent("Purchase currency", value: "\(LocalCurrency.current()) (from your time zone)")
                    .font(.subheadline)
                Button {
                    Task {
                        refreshing = true
                        fxResult = nil
                        let outcome = await FXService.backfill(in: context)
                        fxResult = outcome.text
                        refreshing = false
                        AccessibilityNotification.Announcement(outcome.text).post()
                    }
                } label: {
                    HStack {
                        Text(refreshing ? "Updating rates…" : "Update Exchange Rates")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .font(.subheadline)
                .disabled(refreshing)
                if let fxResult {
                    Text(fxResult).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                BoldHeader("Currency")
            } footer: {
                Text("Purchases in other currencies are converted to \(home) at that day's European Central Bank rate.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Currency")
    }
}
