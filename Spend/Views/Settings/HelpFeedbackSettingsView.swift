import SwiftUI
import UIKit

/// Settings › Help & Feedback: the Apple Pay setup guide again for anyone
/// who skipped it, a feedback email, and the two site links.
struct HelpFeedbackSettingsView: View {
    /// Where it was opened from, for `help_opened`'s `source`.
    var source: HelpSource = .settings
    @Environment(\.openURL) private var openURL
    /// No mail app to open: show the address instead.
    @State private var showingAddress = false
    @State private var copied = false
    /// Counts "Show Tips Again" taps that took effect, for the confirm haptic.
    @State private var tipsReset = 0
    @State private var tipsNeedRelaunch = false

    static let supportEmail = "support@sortd.page"
    static let privacyURL = URL(string: "https://sortd.page/privacy") ?? URL(fileURLWithPath: "/")
    static let supportURL = URL(string: "https://sortd.page/support") ?? URL(fileURLWithPath: "/")

    /// `help_opened` with what was opened and from where.
    private func track(_ topic: HelpTopic) {
        HelpTopic.track(topic, source: source)
    }

    var body: some View {
        List {
            ListPageTitle(title: "Help & Feedback")
            Section {
                NavigationLink {
                    SetupGuideView()
                        .onAppear { track(.setupGuide) }
                } label: {
                    Label("Set Up Apple Pay Logging", systemImage: "wave.3.right")
                }
                Button {
                    track(.sendFeedback)
                    openURL(feedbackURL) { accepted in
                        if !accepted { showingAddress = true }
                    }
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
                Button {
                    track(.reportProblem)
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
                    track(.runSetupAgain)
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
                    track(.showTipsAgain)
                    if TipState.showTipsAgain() { tipsReset += 1 } else { tipsNeedRelaunch = true }
                } label: {
                    Label("Show Tips Again", systemImage: "lightbulb")
                }
                Button {
                    track(.showIntroAgain)
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
                Link(destination: Self.privacyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .simultaneousGesture(TapGesture().onEnded { track(.privacyPolicy) })
                Link(destination: Self.supportURL) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                .simultaneousGesture(TapGesture().onEnded { track(.support) })
            } header: {
                BoldHeader("Website")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Help & Feedback")
        .alert("Email Us", isPresented: $showingAddress) {
            Button("Copy Address") {
                track(.supportEmail)
                UIPasteboard.general.string = Self.supportEmail
                copied = true
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mail isn't set up on this iPhone. Send your feedback to \(Self.supportEmail) from any email app.")
        }
        .feedback(.confirm, trigger: copied)
        .feedback(.confirm, trigger: tipsReset)
        .onAppear { track(.help) }
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

/// `help_opened`'s `topic`: the help page itself, or the row tapped on it.
/// Fixed words only (10 Oct 2026: the event had no properties at all).
enum HelpTopic: String {
    case help
    case setupGuide = "setup_guide"
    case sendFeedback = "send_feedback"
    case reportProblem = "report_problem"
    case supportEmail = "support_email"
    case runSetupAgain = "run_setup_again"
    case showTipsAgain = "show_tips_again"
    case showIntroAgain = "show_intro_again"
    case privacyPolicy = "privacy_policy"
    case support
    /// "Learn more" under Check the Shortcut's result.
    case learnMore = "learn_more"

    static func properties(_ topic: HelpTopic, source: HelpSource) -> [String: Analytics.AnalyticsValue] {
        ["topic": .string(topic.rawValue), "source": .string(source.rawValue)]
    }

    @MainActor static func track(_ topic: HelpTopic, source: HelpSource) {
        Analytics.shared.track(.helpOpened, properties(topic, source: source))
    }
}

/// `help_opened`'s `source`: where the help was opened from.
enum HelpSource: String {
    case settings
    case setupPanel = "setup_panel"
}
