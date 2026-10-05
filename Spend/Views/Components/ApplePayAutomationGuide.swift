import SwiftUI

/// The iOS 26 walk-through: one page per screen of Shortcuts, with a drawing
/// of that screen, what to tap in order, and a button back to Shortcuts.
///
/// On iOS 26 nobody can download this setup (`ApplePaySetupSteps.Route`), so
/// the person builds a Wallet automation by hand and reads this as they go.
/// They leave for Shortcuts after every page, so the page is remembered
/// (`automationPageKey`) and still there when they come back.
struct ApplePayAutomationGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(ApplePaySetupSteps.automationPageKey) private var storedPage = 0
    @AppStorage(ApplePaySetupSteps.automationBuiltKey) private var built = false

    /// The drawn Shortcuts screen grows with Dynamic Type so its text never clips.
    @ScaledMetric(relativeTo: .subheadline) private var scaledMockHeight: CGFloat = 250
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The drawing stops growing where its type does. At accessibility sizes
    /// it gives way: the words are what must stay on screen.
    private var mockHeight: CGFloat { typeSize.isAccessibilitySize ? 200 : min(scaledMockHeight, 320) }

    private let steps = ApplePaySetupSteps.automationSteps
    private var page: Int { min(max(storedPage, 0), steps.count - 1) }
    private var step: ApplePaySetupSteps.AutomationStep { steps[page] }
    private var isLast: Bool { page == steps.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progress
                    // A picture of a screen, not text to read: past xxxLarge its
                    // blue tokens ran off the side and widened the whole sheet
                    // (AX5 check, 5 Oct 2026). The words below scale fully.
                    ShortcutsMock(step: step.id, route: .automation)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(height: mockHeight)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(step.title)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(step.taps.enumerated()), id: \.offset) { index, tap in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
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
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // In the page, not the button bar: at large text the
                        // bar would otherwise cover half the screen.
                        Label("To come back, tap \u{25C0} Sortd at the top left of Shortcuts.",
                              systemImage: "arrow.uturn.backward")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.page)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Step \(page + 1) of \(steps.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    /// One bar per page, filled up to this one.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(steps) { s in
                Capsule()
                    .fill(s.id <= page ? Color.ink : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    /// The page whose Shortcuts button was last tapped. Until it is, that
    /// button is the bold one (go and do the step); after, Next is.
    @State private var openedOn: Int?

    private var bottomBar: some View {
        let cameBack = openedOn == page
        return VStack(spacing: 10) {
            // Page 1 starts the automation; after that the same button goes
            // back to Shortcuts, where the half-made automation is waiting
            // (checked on iOS 26.5: it stays where it was left).
            bold(!cameBack) {
                openedOn = page
                openURL(page == 0 ? ApplePaySetupSteps.createAutomationURL : ApplePaySetupSteps.shortcutsURL)
            } label: {
                Label(page == 0 ? "Start in Shortcuts" : "Back to Shortcuts", systemImage: "arrow.up.forward.app")
            }

            HStack(spacing: 10) {
                if page > 0 {
                    // A chevron, not the word: at the largest text sizes
                    // "Back" wrapped to "Bac / k" and the bar ate the page.
                    Button {
                        withAnimation(.snappy) { storedPage = page - 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: ButtonMetrics.labelHeight)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityLabel("Back")
                }
                bold(cameBack) {
                    if isLast {
                        built = true
                        storedPage = 0
                        dismiss()
                    } else {
                        withAnimation(.snappy) { storedPage = page + 1 }
                    }
                } label: {
                    Text(isLast ? "I'm Done" : "Next")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.page)
    }

    /// A full-width button: the brand fill when it is the next thing to tap,
    /// plain glass otherwise.
    @ViewBuilder
    private func bold<L: View>(_ isBold: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        let content = label()
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: ButtonMetrics.labelHeight)
        if isBold {
            Button(action: action) { content.foregroundStyle(Color.onBrand) }
                .buttonStyle(.glassProminent)
                .tint(Color.brand)
                .controlSize(.large)
        } else {
            Button(action: action) { content.foregroundStyle(Color.ink) }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }
}
