import SwiftUI
import UIKit

/// Settings › Help & Feedback: the Apple Pay setup guide again for anyone
/// who skipped it, a feedback email, and the two site links.
struct HelpFeedbackSettingsView: View {
    @Environment(\.openURL) private var openURL
    /// No mail app to open: show the address instead.
    @State private var showingAddress = false
    @State private var copied = false
    /// Counts "Show Tips Again" taps that took effect, for the confirm haptic.
    @State private var tipsReset = 0
    @State private var tipsNeedRelaunch = false

    static let supportEmail = "support@sortd.page"

    var body: some View {
        List {
            ListPageTitle(title: "Help & Feedback")
            Section {
                NavigationLink {
                    SetupGuideView()
                } label: {
                    Label("Set Up Apple Pay Logging", systemImage: "wave.3.right")
                }
                Button {
                    openURL(feedbackURL) { accepted in
                        if !accepted { showingAddress = true }
                    }
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
                Button {
                    // Setup opens once Settings has finished closing.
                    Router.shared.pendingRerun = true
                    Router.shared.showingSettings = false
                } label: {
                    Label("Run Setup Again", systemImage: "arrow.counterclockwise")
                }
                Button {
                    // TipKit's reset can fail while its store is open; the
                    // counters are cleared either way and the reset runs at
                    // the next launch.
                    if TipState.showTipsAgain() { tipsReset += 1 } else { tipsNeedRelaunch = true }
                } label: {
                    Label("Show Tips Again", systemImage: "lightbulb")
                }
            } header: {
                BoldHeader("Get Help")
            } footer: {
                Text("Feedback opens Mail with your app version, iOS version and iPhone model. Nothing else is added. Running setup again keeps your purchases and cards. Tips are the short notes that point out what a screen can do.")
            }

            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            } header: {
                BoldHeader("Website")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Help & Feedback")
        .alert("Email Us", isPresented: $showingAddress) {
            Button("Copy Address") {
                UIPasteboard.general.string = Self.supportEmail
                copied = true
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mail isn't set up on this iPhone. Send your feedback to \(Self.supportEmail) from any email app.")
        }
        .feedback(.confirm, trigger: copied)
        .feedback(.confirm, trigger: tipsReset)
        .alert("Tips Will Come Back", isPresented: $tipsNeedRelaunch) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reopen Sortd to see them.")
        }
    }

    /// A pre-filled mailto with just enough to debug a report: app version,
    /// iOS version and device model. No purchases, no account — nothing
    /// that identifies who's asking.
    private var feedbackURL: URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let system = UIDevice.current.systemVersion
        let model = Self.deviceIdentifier
        let body = "\n\n—\nSortd \(version) (\(build))\niOS \(system)\n\(model)"
        var components = URLComponents(string: "mailto:\(Self.supportEmail)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Sortd Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:\(Self.supportEmail)")!
    }

    /// The raw hardware identifier (e.g. "iPhone15,2"), not a friendly
    /// name — useful in a bug report without asking anything of the user.
    private static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
