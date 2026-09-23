import SwiftUI
import SwiftData
import UserNotifications

/// Your data: what's stored, where, and the controls to take it out or
/// wipe it. Required reading for the App Store privacy review, and simply
/// fair to users.
struct PrivacyView: View {
    var body: some View {
        List {
            ListPageTitle(title: "Privacy")
            Section {
                row("iphone", "Stored on this iPhone", "Purchases, cards and settings are stored only on this iPhone. There's no Sortd server or account.")
                if Features.gmail {
                    row("envelope", "Gmail, read on this iPhone", "Sortd only looks for receipts and bank alerts. Nothing is copied to a server or shared. Disconnect any time.")
                    row("key", "Google sign-in kept safe", "Your Gmail sign-in is kept in the iPhone Keychain, Apple's secure storage.")
                }
                row("building.columns", "No bank logins", "Sortd never asks for your bank username or password.")
                row("number", "Only the last 4 digits", "Cards are matched by their last 4 digits. Full card numbers are never asked for or stored.")
                row("arrow.left.arrow.right", "Exchange rates", "Daily rates come from frankfurter.dev. Only currency codes and dates are sent.")
                row("chart.bar.xaxis", "No ads, no tracking", "No advertising, no analytics, and nothing is sold or shared.")
            }
            Section {
                Text("Sortd isn't a bank, can't move money and doesn't give financial advice. Amounts come from Apple Pay, receipts and what you type, so check your bank statement for exact figures.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                BoldHeader("Good to Know")
            }
            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
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
        // A Gmail sync still downloading would otherwise save its purchases
        // into the empty store afterwards.
        GmailSync.cancelRunningSyncs()
        try? context.delete(model: Transaction.self)
        try? context.delete(model: MerchantRule.self)
        try? context.delete(model: ImportedRecord.self)
        try? context.delete(model: FXRate.self)
        try? context.save()
        let gmail = GmailSync.accounts
        GmailSync.accounts = []
        // Also picks up revokes that failed earlier, which the wipe below
        // would otherwise lose.
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
