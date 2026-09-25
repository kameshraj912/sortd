import SwiftUI
import SwiftData
import UserNotifications

/// A few plain facts about privacy, then a link to the full policy on the
/// website. The detail used to live here as bullet lists; it's now at
/// sortd.page/privacy.
struct PrivacyView: View {
    /// Observable: the switch redraws when the flag changes.
    private let analytics = Analytics.shared

    var body: some View {
        List {
            ListPageTitle(title: "Privacy")
            Section {
                row("iphone", "Your purchases stay on this phone")
                Toggle(isOn: Binding(
                    get: { analytics.isEnabled },
                    set: { on in
                        // Off: the facade sends one .analyticsOptedOut, then nothing.
                        if !on { log.notice("analytics: switch off, \(Analytics.Event.analyticsOptedOut.rawValue) then nothing") }
                        analytics.isEnabled = on
                    })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share usage data")
                        Text("Usage counts, never amounts. Turn off anytime.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Counts what you use, never what you spend.")
                row("ladybug", "Crash reports have no purchase data")
            }
            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
            .tint(Color.ink)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Privacy")
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
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
        #if SORTD_ICLOUD
        // The iCloud copy goes too, or it would bring everything back. The
        // switch goes off first so the saves below don't schedule a backup;
        // the delete itself runs after the defaults wipe below, so its
        // "still pending" note survives if iCloud can't be reached.
        let cloud = CloudBackup.shared
        let cloudWasOn = cloud.isEnabled
        cloud.isEnabled = false
        #endif
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
        #if SORTD_SIGNIN
        // The account lives in its own Keychain service: sign out by name.
        // Signed in, the PostHog person goes too: its delete is queued here,
        // kept across the wipe below, and sent at the end.
        let account = AccountStore.shared
        account.signOutForDeleteAll()
        #endif
        // Any backup or spreadsheet copies made for sharing.
        Exports.clear()
        CardBook.shared.replaceAll([])
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        // The wipe deletes the analytics switch and reset() clears PostHog's
        // own opt-out; both are put back, so "off" survives Delete All.
        let wipeDefaults = {
            Analytics.shared.preserveConsent {
                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
                // Back to an anonymous analytics id.
                Analytics.shared.signedOut()
            }
        }
        #if SORTD_SIGNIN
        account.preservePendingDeletes(across: wipeDefaults)
        #else
        wipeDefaults()
        #endif
        // The tips start over too. Their counters went with the defaults;
        // TipKit's own store is reset at the next launch, before it opens
        // (a reset while it is open can fail).
        TipState.resetAtNextLaunch()
        // Recreate the saved (empty) card list so old cards can't come back,
        // and set these explicitly so open screens notice and setup reopens.
        CardBook.shared.replaceAll([])
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        UserDefaults.standard.set(false, forKey: OnboardingView.doneKey)
        // Widgets were showing the old totals until the next app refresh.
        WidgetBridge.refresh(from: context)
        #if SORTD_ICLOUD
        if cloudWasOn { Task { await cloud.deleteCloudCopyAfterReset() } }
        #endif
        #if SORTD_SIGNIN
        Task { await account.retryPendingDeletes() }
        #endif
    }
}
