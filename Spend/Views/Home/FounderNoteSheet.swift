import SwiftUI
import UIKit

/// The founder's note (a letter from Raj, final copy "D"): shown once, at
/// the aha moment straight after the first automatically logged purchase's
/// celebration (`ActivationCard`) has played, and any time after that from
/// Settings › About › "Read the note from Kameshraj".
enum FounderNote {
    /// Where the note was opened from, for `Analytics.Event.founderNoteSeen`.
    enum Moment: String { case aha, about }

    /// Set the first time the note is shown, from either moment. Once set,
    /// the aha moment never offers it again; About can still open it.
    static let seenAtKey = "founderNoteSeenAt"

    static func hasBeenSeen(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: seenAtKey) != nil
    }

    static func markSeen(defaults: UserDefaults = .standard, now: Date = .now) {
        guard defaults.object(forKey: seenAtKey) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: seenAtKey)
    }

    /// The pure "should show now?" rule for the aha moment, kept free of
    /// SwiftUI, UserDefaults and `Activation` so it is testable on its own
    /// (`SpendTests/FounderNoteTests.swift`).
    ///
    /// - `hasFirstAutoPurchase`: the first purchase Sortd logged by itself
    ///   (a `.tap` or `.email` source transaction, the same rule
    ///   `Activation.detect` uses) has landed.
    /// - `seenBefore`: the note has already been shown once, ever.
    /// - `setupDone`: onboarding has finished (never during setup).
    /// - `anotherSheetOrAlertShowing`: any other sheet, alert or confirmation
    ///   is already on screen.
    static func shouldShowAtAha(hasFirstAutoPurchase: Bool, seenBefore: Bool, setupDone: Bool,
                                 anotherSheetOrAlertShowing: Bool) -> Bool {
        hasFirstAutoPurchase && !seenBefore && setupDone && !anotherSheetOrAlertShowing
    }
}

/// A 44pt circle with a "K" in the brand gradient. No photo.
struct FounderAvatar: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color.brandPalette[0], Color.brandPalette[2]],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 44, height: 44)
            .overlay {
                Text("K")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Raj's letter, read once at the aha moment and any time after from
/// Settings › About. Dismiss keeps going with the app; "Tell Kameshraj"
/// opens the same feedback email path as Settings › Help & Feedback.
struct FounderNoteSheet: View {
    let moment: FounderNote.Moment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// No mail app to open: same fallback as Help & Feedback.
    @State private var showingAddress = false

    private let paragraphs: [String] = [
        "Thank you for using Sortd. That tap you just made logged itself. That's the whole idea.",
        "I made Sortd with two rules:",
    ]

    private let bullets: [String] = [
        "No typing. Pay as usual and it's written down.",
        "No bank login, no account. Your purchases stay on this iPhone.",
    ]

    private let closing = "I hope it gives you the same clear picture it gave me. If anything feels off, or you have an idea, tell me. I read every message."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(alignment: .leading, spacing: 16) {
                    Text(paragraphs[0])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(paragraphs[0])
                    Text(paragraphs[1])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(paragraphs[1])
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(bullets, id: \.self) { line in
                            Label {
                                Text(line)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(line)
                        }
                    }
                    Text(closing)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(closing)
                }
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)

                signature
            }
            .padding(20)
            // Room so the last line never sits under the pinned buttons.
            .padding(.bottom, 92)
        }
        .safeAreaInset(edge: .bottom) {
            buttons
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.thinMaterial)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.page)
        .onAppear {
            Analytics.shared.track(.founderNoteSeen, ["moment": .string(moment.rawValue)])
            FounderNote.markSeen()
        }
        .alert("Email Us", isPresented: $showingAddress) {
            Button("Copy Address") {
                UIPasteboard.general.string = HelpFeedbackSettingsView.supportEmail
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mail isn't set up on this iPhone. Send your feedback to \(HelpFeedbackSettingsView.supportEmail) from any email app.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FounderAvatar()
            VStack(alignment: .leading, spacing: 2) {
                Text("It worked.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.ink)
                Text("A note from Kameshraj")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var signature: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("— Kameshraj")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
            Text("Made in Melbourne and Singapore")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Keep going").primaryPill()
            }
            .primaryGlass()
            .accessibilityLabel("Keep going")

            Button {
                Analytics.shared.track(.founderNoteReplyTapped)
                openURL(feedbackURL) { accepted in
                    if !accepted { showingAddress = true }
                }
                dismiss()
            } label: {
                Text("Tell Kameshraj")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.ink)
            }
            .secondaryGlass()
            .accessibilityLabel("Tell Kameshraj")
            .accessibilityHint("Opens an email to send feedback")
        }
        .padding(.top, 4)
    }

    /// The same blank mailto Settings › Help & Feedback uses.
    private var feedbackURL: URL {
        var components = URLComponents(string: "mailto:\(HelpFeedbackSettingsView.supportEmail)")!
        components.queryItems = [URLQueryItem(name: "subject", value: "Sortd feedback")]
        return components.url ?? URL(string: "mailto:\(HelpFeedbackSettingsView.supportEmail)")!
    }
}
