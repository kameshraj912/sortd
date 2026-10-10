import SwiftUI

/// An iOS 26 walk-through: one page per screen of Shortcuts, with a drawing
/// of that screen, what to tap in order, and a button over to Shortcuts.
///
/// Written for someone who has never opened Shortcuts (Raj, 5 Oct 2026:
/// "as if an old person is using the app"): one tap per line, short words.
/// It looks like the rest of setup on purpose, same type and same buttons;
/// a first pass with its own larger type and square buttons read as a
/// different app. The person leaves for Shortcuts after every page, so the
/// page is remembered and still there when they come back.
struct ApplePayAutomationGuide: View {
    let steps: [ApplePaySetupSteps.AutomationStep]
    /// Which set of drawings goes with `steps`.
    let drawing: WalletSetupGuide.Route
    /// The connection as the caller sees it, for `apple_pay_setup_action`.
    var status: ApplePayStatus = .notConnected

    @State private var safariPage: SafariPage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage private var storedPage: Int
    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var built = false
    @ScaledMetric(relativeTo: .subheadline) private var scaledMockHeight: CGFloat = 215
    /// The drawing stops growing where its type does. At accessibility sizes
    /// it gives way: the words are what must stay on screen.
    private var mockHeight: CGFloat { typeSize.isAccessibilitySize ? 200 : min(scaledMockHeight, 320) }

    init(steps: [ApplePaySetupSteps.AutomationStep], drawing: WalletSetupGuide.Route,
         status: ApplePayStatus = .notConnected) {
        self.steps = steps
        self.drawing = drawing
        self.status = status
        _storedPage = AppStorage(wrappedValue: 0, ApplePaySetupSteps.automationPageKey)
    }

    private var page: Int { min(max(storedPage, 0), steps.count - 1) }

    /// A note, with the support page's address turned into a link.
    private func noteText(_ note: String) -> AttributedString {
        var text = AttributedString(note)
        if let range = text.range(of: ApplePaySetupSteps.missingFromListLinkText) {
            text[range].link = ApplePaySetupSteps.missingFromListURL
            text[range].underlineStyle = .single
        }
        return text
    }

    /// `apple_pay_setup_action` from inside the guide.
    private func trackAction(_ action: String, page: Int? = nil) {
        ApplePaySetupSteps.trackAction(action, status: status, saysBuilt: built, page: page)
    }

    /// Someone whose downloaded shortcut once reached Sortd made the old
    /// kind of automation; the first page tells them to delete it.
    private var madeOldAutomation: Bool { LogPurchaseIntent.shortcutHasReachedApp }
    private var step: ApplePaySetupSteps.AutomationStep { steps[page] }
    private var isLast: Bool { page == steps.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    progress
                    // The same heading as every setup page: bold title, the four dashes.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        BrandBar(width: 14, height: 3)
                    }
                    // A picture of a screen, not text to read: past xxxLarge its
                    // blue tokens ran off the side and widened the whole sheet
                    // (AX5 check, 5 Oct 2026). The words below scale fully.
                    ShortcutsMock(step: step.id, route: drawing)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(height: mockHeight)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(step.taps.enumerated()), id: \.offset) { index, tap in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color.brandPalette[0], in: .circle)
                                    .accessibilityHidden(true)
                                Text(tap)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(index + 1). \(tap)")
                        }
                        if let note = step.note {
                            Text(noteText(note))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                // Links in a note open in the in-app Safari sheet, not the default browser.
                                .environment(\.openURL, OpenURLAction { url in
                                    safariPage = SafariPage(url: url)
                                    return .handled
                                })
                        }
                        if page == 0, madeOldAutomation {
                            Label(ApplePaySetupSteps.oldAutomationLine, systemImage: "exclamationmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    comeBackTip
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.page)
            .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle("Step \(page + 1) of \(steps.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(item: $safariPage) { page in
                SafariSheet(url: page.url).ignoresSafeArea()
            }
        }
        .analyticsScreen(.applePayGuide(page: page + 1))
    }

    /// One bar per page, filled up to this one.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(steps) { s in
                Capsule()
                    .fill(s.id <= page ? Color.ink : Color.secondary.opacity(0.25))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    /// How to get back, said in the page and at reading size: the small grey
    /// line it started as was the first thing missed.
    private var comeBackTip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
            Text("When you have done this, come back to Sortd. Tap \u{25C0} Sortd at the top left of the screen.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
    }

    /// The same two buttons as every setup screen: the glass one goes to
    /// Shortcuts, the filled one moves on. Each keeps its style for good;
    /// swapping styles as the person came and went rebuilt the buttons and
    /// dropped taps (simulator check, 5 Oct 2026).
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                // Page 1 starts the automation; after that the same button goes
                // back to Shortcuts, where the half-made automation is waiting
                // (checked on iOS 26.5: it stays where it was left).
                Button {
                    trackAction(page == 0 ? "start_in_shortcuts" : "back_to_shortcuts", page: page + 1)
                    let url = page == 0 ? ApplePaySetupSteps.createAutomationURL : ApplePaySetupSteps.shortcutsURL
                    // If the direct link is refused, plain Shortcuts still opens.
                    openURL(url) { accepted in
                        if !accepted { openURL(ApplePaySetupSteps.shortcutsURL) }
                    }
                } label: {
                    Label(page == 0 ? "Start in Shortcuts" : "Back to Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                HStack(spacing: 10) {
                    if page > 0 {
                        // A chevron, not the word: at the largest text sizes
                        // "Back" wrapped to "Bac / k" and the bar ate the page.
                        Button {
                            storedPage = page - 1
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .foregroundStyle(Color.ink)
                                .frame(width: 28, height: ButtonMetrics.labelHeight)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .accessibilityLabel("Back")
                    }
                    Button {
                        if isLast {
                            trackAction("guide_done", page: page + 1)
                            built = true
                            storedPage = 0
                            dismiss()
                        } else {
                            trackAction("guide_next", page: page + 1)
                            storedPage = page + 1
                        }
                    } label: {
                        Text(isLast ? "I'm Done" : "Next")
                            .font(.headline)
                            .foregroundStyle(Color.onBrand)
                            .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.brand)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
