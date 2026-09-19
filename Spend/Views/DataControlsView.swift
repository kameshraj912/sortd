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
                row("iphone", "Stored on this iPhone", "Purchases, cards and settings live only in Sortd's storage on your iPhone. There's no Sortd server or account.")
                row("envelope", "Gmail, read on your iPhone", "If you connect Gmail, Sortd searches only for receipts and bank alerts and reads them on this iPhone. Emails are never copied to a server, shared, or used for anything else. Disconnect any time in Settings.")
                row("key", "Keys in the Keychain", "The key that lets Sortd read your receipts is kept in the iPhone Keychain, not in the app's files.")
                row("building.columns", "No bank logins", "Sortd never asks for your bank username or password.")
                row("number", "Only the last 4 digits", "Cards are matched by their last 4 digits. Full card numbers are never asked for or stored.")
                row("arrow.left.arrow.right", "Exchange rates", "To convert currencies, Sortd downloads daily rates from frankfurter.dev. Only a currency code and dates are sent, nothing about you.")
                row("chart.bar.xaxis", "No ads, no tracking", "No advertising, no analytics, and nothing is sold or shared.")
            }
            Section {
                Text("Sortd helps you track your own spending. It isn't a bank and doesn't move money, and nothing in it is financial advice. Amounts come from your receipts and bank alerts, and converted amounts use published exchange rates, so always check your bank statement for exact figures.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                BoldHeader("Good to Know")
            }
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
    static func file(_ transactions: [Transaction]) -> URL? {
        let iso = ISO8601DateFormatter()
        var lines = ["date,merchant,amount,currency,amount_\(Money.home.lowercased()),category,card,refunded,note"]
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            let fields = [iso.string(from: t.date), t.merchant, "\(t.amount)", t.currencyCode,
                          t.audAmount.map { "\($0)" } ?? "", t.category.name, t.card.name,
                          t.refunded ? "yes" : "no", t.note]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sortd purchases \(Date.now.formatted(.iso8601.year().month().day())).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Quotes a field when it has a comma, quote or line break.
    nonisolated static func escape(_ s: String) -> String {
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
        Task { for a in gmail { await GoogleAuth.disconnect(a.email) } }
        Keychain.deleteAll()
        // The exported spreadsheet, if one was made.
        for f in (try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "csv" { try? FileManager.default.removeItem(at: f) }
        CardBook.shared.replaceAll([])
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        // Recreate the saved (empty) card list so old cards can't come back,
        // and set these explicitly so open screens notice and setup reopens.
        CardBook.shared.replaceAll([])
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        UserDefaults.standard.set(false, forKey: OnboardingView.doneKey)
    }
}
