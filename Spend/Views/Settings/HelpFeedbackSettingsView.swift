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
                    openURL(reportProblemURL) { accepted in
                        if !accepted { showingAddress = true }
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Report a Problem")
                            Text("Crash reports are sent automatically when sharing is on.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "ladybug")
                    }
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
                Button {
                    // The intro opens once Settings has finished closing.
                    Router.shared.pendingIntroReplay = true
                    Router.shared.showingSettings = false
                } label: {
                    Label("Show the Intro Again", systemImage: "sparkles")
                }
            } header: {
                BoldHeader("Get Help")
            } footer: {
                Text("Setup again keeps your purchases and cards.")
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

    /// A blank mailto. No app version, no device info — just an empty
    /// message the person writes themselves.
    private var feedbackURL: URL {
        var components = URLComponents(string: "mailto:\(Self.supportEmail)")!
        components.queryItems = [URLQueryItem(name: "subject", value: "Sortd feedback")]
        return components.url ?? URL(string: "mailto:\(Self.supportEmail)")!
    }

    /// A pre-filled mailto with just the app version, so a bug report can
    /// be matched to a build. No iOS version, no device model, no purchases.
    private var reportProblemURL: URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let body = "\n\n—\nSortd \(version) (\(build))"
        var components = URLComponents(string: "mailto:\(Self.supportEmail)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Sortd problem"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:\(Self.supportEmail)")!
    }
}
