import SwiftUI
import UIKit

/// Settings › Help & Feedback: the Apple Pay setup guide again for anyone
/// who skipped it, a feedback email, and the two site links.
struct HelpFeedbackSettingsView: View {
    var body: some View {
        SettingsList {
            ListPageTitle(title: "Help & Feedback", subtitle: "Get set up, get help, or tell us what's wrong.")
            Section {
                NavigationLink {
                    SetupGuideView()
                } label: {
                    Label("Apple Pay Setup Guide", systemImage: "wave.3.right")
                }
                Link(destination: feedbackURL) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            } header: {
                BoldHeader("Get Help")
            }

            Section {
                Link(destination: URL(string: "https://sortd.page/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://sortd.page/support.html")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            } header: {
                BoldHeader("Online")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Help & Feedback")
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
        var components = URLComponents(string: "mailto:support@sortd.page")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Sortd Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:support@sortd.page")!
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
