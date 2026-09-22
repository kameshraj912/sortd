import SwiftUI
import SwiftData
import UserNotifications

/// Your data: what's stored, where, and the controls to take it out or
/// wipe it. Required reading for the App Store privacy review, and simply
/// fair to users.
struct PrivacyView: View {
    var body: some View {
        List {
            ListPageTitle(title: "Privacy", subtitle: "What Sortd stores, and where.")
            Section {
                row("iphone", "On This iPhone", "Purchases, cards and settings are stored locally — no server, no account.")
                if Features.gmail {
                    row("envelope", "Gmail, Read-Only", "Limited to receipts and bank alerts, processed on this iPhone.")
                }
                row("key", "Encrypted", "The key that unlocks your email is encrypted at rest.")
                row("building.columns", "No Bank Logins", "Bank usernames and passwords are never requested.")
                row("number", "Only the Last 4 Digits", "Full card numbers are never requested or stored.")
                row("chart.bar.xaxis", "No Ads, No Tracking", "No advertising, no analytics, nothing sold or shared.")
                // Only when reports really go out: a TestFlight build with a
                // Sentry DSN. Otherwise this row would claim something false.
                if CrashReporting.isOn {
                    row("ladybug", "Crash Reports in Beta", "Limited to the crash and device model — never your purchases.")
                }
            }
            Section {
                Text("Sortd isn't a bank and doesn't give financial advice. Check your bank statement for exact amounts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Read the full privacy policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/terms")!) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            }
            .tint(Color.ink)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Privacy")
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(Color.ink).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Every purchase as a CSV file, for Numbers, Excel or another app.
enum CSVExport {
    static func data(_ transactions: [Transaction]) -> Data {
        let iso = ISO8601DateFormatter()
        var lines = ["date,merchant,amount,currency,amount_\(Money.home.lowercased()),category,card,refunded,note"]
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            let fields = [iso.string(from: t.date), t.merchant, "\(t.amount)", t.currencyCode,
                          t.audAmount.map { "\($0)" } ?? "", t.category.name, t.card.name,
                          t.refunded ? "yes" : "no", t.note]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Makes a field safe for a spreadsheet. Merchant names and notes can come
    /// from emails, so a cell starting with = + - @ (or a tab or return) gets a
    /// leading ' and can't run as a formula. Then quotes it when it has a comma,
    /// quote or line break.
    nonisolated static func escape(_ s: String) -> String {
        var s = s
        if let first = s.first, "=+-@\t\r".contains(first) { s = "'" + s }
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Removes everything Sortd has stored and starts setup again.
@MainActor
enum DataReset {
    static func deleteEverything(in context: ModelContext) {
        try? context.delete(model: Transaction.self)
        try? context.delete(model: MerchantRule.self)
        try? context.delete(model: ImportedRecord.self)
        try? context.delete(model: FXRate.self)
        try? context.save()
        let gmail = GmailSync.accounts
        GmailSync.accounts = []
        GoogleAuth.revokeAll(gmail.map(\.email))
        Keychain.deleteAll()
        #if DEBUG
        CompedPro.clear()
        #endif
        // Any backup or spreadsheet copies made for sharing.
        Exports.clear()
        CardBook.shared.replaceAll([])
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        // Recreate the saved (empty) card list so old cards can't come back,
        // and set these explicitly so open screens notice and setup reopens.
        CardBook.shared.replaceAll([])
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        UserDefaults.standard.set(false, forKey: OnboardingView.doneKey)
        // Widgets were showing the old totals until the next app refresh.
        WidgetBridge.refresh(from: context)
    }
}
