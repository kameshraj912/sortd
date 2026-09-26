import SwiftUI
import UIKit

/// The three-step app intro (`docs/specs/2026-09-26-app-intro-v2.md`, option A,
/// "stories"): the real screen behind it, a cutout that keeps the control the
/// step is about at full brightness, and either
/// - **motion allowed** (Reduce Motion off, VoiceOver off): three thin
///   progress segments at the top, a card with a small "N of 3" eyebrow and
///   a secondary Skip button sharing that row (no Next), the line below,
///   real per-step motion (a finger tapping, or the tab bar's own ring),
///   auto-advance after `IntroStep.stepDuration`, a tap anywhere advances
///   early, a finger held down pauses the clock; or
/// - **Reduce Motion, or VoiceOver running** (kept exactly as first built,
///   the spec's own fallback): a still ring, the old "Step N of 3" heading,
///   cross-fading steps, and real Next/Done + Skip buttons in the card —
///   nothing times out.
///
/// `RootView` drives the selected tab from `tour.step`, so the highlighted
/// control is real, and threads the day header's measured frame in from
/// `ActivityView` via `IntroDayHeaderKey` for the `.move` step.
struct IntroOverlay: View {
    @Binding var tour: IntroTour
    /// The day header's frame (chevrons + day title), measured by
    /// `ActivityView.pagerHeader` and read at `RootView` via
    /// `.overlayPreferenceValue(IntroDayHeaderKey.self)`. Nil until
    /// `ActivityView` has laid out at least once on step `.move`, or if it
    /// never can be (see `IntroDayHeaderKey`'s doc) — either way this falls
    /// back to the whole tab bar band, same as `.add`/`.insights` do today.
    let dayHeaderFrame: CGRect?
    /// The "Older Day" chevron button's own frame (a 44pt square that hangs
    /// out past the header row's measured frame — `pagerHeader`'s negative
    /// horizontal padding), measured the same way as `dayHeaderFrame`. Only
    /// used to place the finger for `.move`; the cutout still uses the
    /// whole header.
    let dayChevronFrame: CGRect?
    /// A tap anywhere, or the classic-mode Next/Done button.
    let onNext: () -> Void
    /// The step's own clock ran out with nobody tapping.
    let onTimeout: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var probe = TabBarLayout()
    @State private var pulse = false
    @State private var fingerOpacity: Double = 0
    @State private var fingerScale: CGFloat = 1
    @State private var countdown: IntroCountdown?
    /// 0...1: how far through the current step's `stepDuration` the poll
    /// loop has gotten, driving the progress segment's fill. Frozen while
    /// `countdown?.isPaused` is true (a held finger).
    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var pressStartedAt: Date?

    /// Whether the step times out on its own: never under Reduce Motion or
    /// with VoiceOver running (`IntroTour.autoAdvances`, the one place both
    /// gates live so neither can be forgotten separately).
    private var autoAdvanceAllowed: Bool {
        IntroTour.autoAdvances(reduceMotion: reduceMotion, voiceOverRunning: voiceOverRunning)
    }

    var body: some View {
        if let step = tour.step {
            // One `GeometryReader` that ignores the safe area itself, so
            // `proxy.size`/`proxy.frame(in: .global)` cover the true, full
            // screen and every child below shares one coordinate frame.
            // Applying `.ignoresSafeArea()` only to the dim layer (as a
            // first pass did) re-based *that* layer's own coordinate origin
            // to the true screen top while `target` was computed against
            // the safe-area-inset frame — the mismatch (a top inset's
            // worth, ~62pt) put the cutout and the ring well off the real
            // button.
            GeometryReader { proxy in
                // The probe measures in the UIKit window's own coordinate
                // space (`convert(_:to: nil)`); SwiftUI's `.global` space is
                // the same space for a single full-screen window, so this is
                // the only place a conversion back to local coordinates
                // happens.
                let origin = proxy.frame(in: .global).origin
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let target = Self.clamp(
                    Self.targetFrame(for: step, probe: probe, dayHeaderFrame: dayHeaderFrame,
                                      screen: proxy.size, safeBottom: proxy.safeAreaInsets.bottom)
                        .offsetBy(dx: -origin.x, dy: -origin.y),
                    to: bounds)
                let pointerX = Self.clampedPointerOffset(target: target, screenWidth: proxy.size.width)
                let approximate = probe.foundNothing && (step != .move || dayHeaderFrame == nil)
                let showButtons = !autoAdvanceAllowed

                ZStack(alignment: .top) {
                    dim(cutout: target)
                    highlight(target, approximate: approximate)
                    finger(at: fingerAnchor(for: step, target: target, chevron: dayChevronFrame))
                    cardLayer(for: step, target: target, pointerOffsetX: pointerX,
                              bounds: bounds, safeBottom: proxy.safeAreaInsets.bottom, showButtons: showButtons)
                    if !showButtons {
                        progressBar(current: step, safeTop: proxy.safeAreaInsets.top)
                    }
                }
                .frame(width: bounds.width, height: bounds.height)
                .id(step)
                .transition(.opacity)
            }
            .ignoresSafeArea()
            .background(TabBarProbe(layout: $probe))
            .accessibilityElement(children: .contain)
            .task(id: step) {
                pulse = false
                fingerOpacity = 0
                progress = 0
                countdown = IntroCountdown(startedAt: .now)
                guard !reduceMotion else { return }
                await playMotion(step)
                guard autoAdvanceAllowed else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let countdown else { continue }
                    let remaining = countdown.remaining(at: .now, duration: IntroStep.stepDuration)
                    progress = 1 - remaining / IntroStep.stepDuration
                    if remaining <= 0 {
                        onTimeout()
                        return
                    }
                }
            }
        }
    }

    // MARK: Motion

    /// Plays once, before the step holds until it's tapped or times out.
    /// `.none` under Reduce Motion — this is only ever called once that's
    /// already been checked.
    private func playMotion(_ step: IntroStep) async {
        switch step.motion(reduceMotion: false) {
        case .none:
            break
        case .ringPulse:
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeInOut(duration: step.motionDuration / 2)) { pulse = true }
            try? await Task.sleep(for: .seconds(step.motionDuration / 2))
            withAnimation(.easeInOut(duration: step.motionDuration / 2)) { pulse = false }
        case .tapTwice:
            fingerOpacity = 1
            await tap()
            try? await Task.sleep(for: .milliseconds(250))
            await tap()
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.25)) { fingerOpacity = 0 }
        case .tapOnce:
            fingerOpacity = 1
            await tap()
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.25)) { fingerOpacity = 0 }
        }
    }

    /// One press-and-release of the simulated finger.
    private func tap() async {
        withAnimation(.easeOut(duration: 0.12)) { fingerScale = 0.7 }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.12)) { fingerScale = 1 }
        try? await Task.sleep(for: .milliseconds(120))
    }

    /// Where the simulated finger lands: the + circle's centre for `.add`,
    /// the "Older Day" chevron button's own centre for `.move` — its measured
    /// frame when `ActivityView` reported one, else a guess inset from the
    /// header's trailing edge (the chevron's 44pt square hangs out past the
    /// header row's own frame, `pagerHeader`'s negative horizontal padding —
    /// close enough only when the real measurement isn't there). `.insights`
    /// has no finger — the ring pulse alone is its motion, on the tab the app
    /// really selects.
    private func fingerAnchor(for step: IntroStep, target: CGRect, chevron: CGRect?) -> CGPoint {
        switch step {
        case .add:
            guard target != .zero else { return .zero }
            return CGPoint(x: target.midX, y: target.midY)
        case .move:
            if let chevron, chevron != .zero { return CGPoint(x: chevron.midX, y: chevron.midY) }
            guard target != .zero else { return .zero }
            return CGPoint(x: target.maxX - 8, y: target.midY)
        case .insights: return .zero
        }
    }

    @ViewBuilder
    private func finger(at point: CGPoint) -> some View {
        if point != .zero, fingerOpacity > 0 {
            Circle()
                .fill(.white.opacity(0.92))
                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                .frame(width: 30, height: 30)
                .scaleEffect(fingerScale)
                .shadow(color: .black.opacity(0.3), radius: 4)
                .opacity(fingerOpacity)
                .position(point)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Dim + cutout

    /// ~55% black with `target` cut out (`.blendMode(.destinationOut)` in a
    /// `compositingGroup`), so the control itself stays at full brightness
    /// instead of dimming along with the rest of the screen. The whole
    /// layer stays tappable, cutout included, so "tap anywhere advances"
    /// still holds over the hole.
    ///
    /// One `DragGesture(minimumDistance: 0)` does both jobs the spec asks
    /// for — a quick tap advances at once, a held finger pauses the clock
    /// and lifting resumes it — rather than stacking a separate
    /// `.onTapGesture` and `.onLongPressGesture` on the same view, which
    /// race for the same touch.
    private func dim(cutout: CGRect) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            if cutout != .zero {
                RoundedRectangle(cornerRadius: cutoutRadius(cutout), style: .continuous)
                    .frame(width: cutout.width + 14, height: cutout.height + 14)
                    .position(x: cutout.midX, y: cutout.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    isPressing = true
                    pressStartedAt = .now
                    if autoAdvanceAllowed { countdown?.pause(at: .now) }
                }
                .onEnded { _ in
                    let heldFor = pressStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
                    isPressing = false
                    if autoAdvanceAllowed { countdown?.resume(at: .now) }
                    // A quick tap advances; a hold just paused/resumed the
                    // clock and shouldn't also skip ahead on release.
                    if heldFor < 0.35 { onNext() }
                }
        )
    }

    private func cutoutRadius(_ frame: CGRect) -> CGFloat { min(frame.width, frame.height) / 2 }

    // MARK: Highlight

    /// A soft white glow ring on the cutout's edge, pulsing gently once
    /// (a still ring under Reduce Motion — no motion, just the glow).
    @ViewBuilder
    private func highlight(_ frame: CGRect, approximate: Bool) -> some View {
        if frame != .zero {
            RoundedRectangle(cornerRadius: cutoutRadius(frame), style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: frame.width + 14, height: frame.height + 14)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: .white.opacity(0.65), radius: reduceMotion ? 3 : (pulse ? 6 : 3))
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.04 : 1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if approximate {
                Image(systemName: "arrow.down")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .position(x: frame.midX, y: max(20, frame.minY - 22))
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Progress bar (motion-allowed mode only)

    /// Three thin segments, Stories-style: full for a step already passed,
    /// empty for one not reached, and filling from `progress` for the one
    /// on screen now. Replaces the card's old "Step N of 3" heading.
    private func progressBar(current: IntroStep, safeTop: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(IntroTour.steps, id: \.self) { s in
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * fraction(for: s, current: current))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, safeTop + 8)
        .accessibilityHidden(true)
    }

    private func fraction(for step: IntroStep, current: IntroStep) -> Double {
        if step.rawValue < current.rawValue { return 1 }
        if step.rawValue > current.rawValue { return 0 }
        return progress
    }

    // MARK: Card

    /// Where the card sits: bottom-anchored, just above the target, for
    /// `.add`/`.insights` (both live in or next to the tab bar, near the
    /// bottom edge); hanging just under the target for `.move` (the day
    /// header sits near the top, under the nav bar) — and for the whole-bar
    /// fallback too, since that target is back at the bottom.
    private func cardLayer(for step: IntroStep, target: CGRect, pointerOffsetX: CGFloat,
                            bounds: CGRect, safeBottom: CGFloat, showButtons: Bool) -> some View {
        let hangsBelow = target != .zero && target.midY < bounds.height / 2
        return Group {
            if hangsBelow {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, target.maxY + 16))
                    card(step, pointerOffsetX: pointerOffsetX, pointerEdge: .top, showButtons: showButtons)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    card(step, pointerOffsetX: pointerOffsetX, pointerEdge: .bottom, showButtons: showButtons)
                }
                .padding(.bottom, max(safeBottom + 8, bounds.height - target.minY + 16))
            }
        }
        .padding(.horizontal, 20)
    }

    private func card(_ step: IntroStep, pointerOffsetX: CGFloat, pointerEdge: Edge, showButtons: Bool) -> some View {
        VStack(spacing: 14) {
            if showButtons {
                VStack(spacing: 6) {
                    Text("Step \(step.rawValue + 1) of \(IntroTour.steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(step.line)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink)
                }
                // One element with the full "Step N of 3. <target>. <line>."
                // label; Skip and Next stay their own reachable buttons below.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(step.accessibilityLabel)
                buttons(step)
            } else {
                VStack(spacing: 6) {
                    // The eyebrow and Skip share a row (eyebrow leading,
                    // Skip trailing); Skip stays a sibling, not folded into
                    // the combined element below, so it reads as its own
                    // accessibility button.
                    HStack(spacing: 8) {
                        Text("\(step.rawValue + 1) of \(IntroTour.steps.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                    }
                    Text(step.line)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(step.accessibilityLabel)
                .overlay(alignment: .topTrailing) { cardSkipButton }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .overlay(alignment: pointerEdge == .bottom ? .bottom : .top) {
            // A solid fill, not `.regularMaterial`: a blurred material on a
            // shape this small rendered as a soft round blob rather than a
            // crisp triangle.
            Triangle()
                .fill(Color(.systemBackground).opacity(0.9))
                .frame(width: 16, height: 8)
                .rotationEffect(pointerEdge == .bottom ? .zero : .degrees(180))
                .offset(x: pointerOffsetX, y: pointerEdge == .bottom ? 7 : -7)
                .accessibilityHidden(true)
        }
    }

    /// Skip is a plain text button on the leading edge; Next/Done is the
    /// prominent button on the trailing edge — both at least 44pt tall.
    /// At accessibility text sizes they stack full-width instead (a
    /// `.glassProminent` capsule with no minimum width wrapped "Next" to
    /// "Nex/t" side by side). Only shown in classic mode (Reduce Motion, or
    /// VoiceOver running) — the motion-allowed mode has no Next button;
    /// Skip there is `cardSkipButton`, in the eyebrow's row instead.
    @ViewBuilder
    private func buttons(_ step: IntroStep) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                nextButton(step).frame(maxWidth: .infinity)
                skipButton.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 12) {
                skipButton
                Spacer(minLength: 8)
                nextButton(step)
            }
        }
    }

    private var skipButton: some View {
        Button("Skip", action: onSkip)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Motion-allowed mode's Skip: a small secondary button sharing the
    /// eyebrow's row, top trailing (originally a floating pill top right of
    /// the whole screen — it sat on top of the settings gear every screen
    /// already draws there, reading as a broken button). Still a real,
    /// 44pt-tall accessibility button, just inside the card now.
    private var cardSkipButton: some View {
        Button("Skip", action: onSkip)
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func nextButton(_ step: IntroStep) -> some View {
        Button(step == .move ? "Done" : "Next", action: onNext)
            .buttonStyle(.glassProminent)
            .tint(Color.brand)
            // The window sets `.foregroundStyle(Color.ink)` further up
            // (`SpendApp`); without this, the label drew ink on ink.
            .foregroundStyle(Color.onBrand)
            .frame(minHeight: 44)
    }

    // MARK: Target frame

    /// Where to draw the cutout: the probe's live UIKit frame when it found
    /// one, the day header's measured frame for `.move`, else a computed
    /// slot over the whole tab bar band (the spec's fallback when the exact
    /// control can't be measured).
    static func targetFrame(for step: IntroStep, probe: TabBarLayout, dayHeaderFrame: CGRect?,
                             screen: CGSize, safeBottom: CGFloat) -> CGRect {
        switch step {
        case .add:
            return probe.addCircle ?? probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
        case .insights:
            // By identity (the item's slot in the bar's left-to-right
            // order), not "whichever item is selected right now": the
            // selection indicator's own frame lags the tab change by a
            // frame or two, which rang Home instead of Insights.
            if let index = AppTab.mainBarOrder.firstIndex(of: .insights), probe.items.indices.contains(index) {
                return probe.items[index]
            }
            return probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
        case .move:
            return dayHeaderFrame ?? probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
        }
    }

    /// The bar's known height (83pt on iOS 26/27's glass bar) plus the
    /// safe area, full width: used only when the probe finds nothing.
    static func fallbackBand(screen: CGSize, safeBottom: CGFloat) -> CGRect {
        let height: CGFloat = 83 + safeBottom
        return CGRect(x: 0, y: screen.height - height, width: screen.width, height: height)
    }

    /// Keeps the cutout and its glow ring fully on screen (the + circle
    /// sits close enough to the trailing and bottom edges that a padded
    /// ring could otherwise poke past both).
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        guard rect != .zero else { return rect }
        let pad: CGFloat = 9 // half the +14 the ring adds around the target
        let minX = bounds.minX + pad, maxX = bounds.maxX - pad
        let minY = bounds.minY + pad, maxY = bounds.maxY - pad
        guard minX < maxX, minY < maxY else { return rect }
        let midX = min(max(rect.midX, minX), maxX)
        let midY = min(max(rect.midY, minY), maxY)
        return CGRect(x: midX - rect.width / 2, y: midY - rect.height / 2, width: rect.width, height: rect.height)
    }

    /// The pointer's x offset from the card's own centre (the card is
    /// itself screen-centred, capped at 360pt wide), clamped so the
    /// triangle stays over the card instead of poking past its corner.
    static func clampedPointerOffset(target: CGRect, screenWidth: CGFloat) -> CGFloat {
        guard target != .zero else { return 0 }
        let cardWidth = min(360, screenWidth - 40)
        let limit = cardWidth / 2 - 20
        let raw = target.midX - screenWidth / 2
        return min(max(raw, -limit), limit)
    }
}

/// A small downward-pointing triangle, for the card's pointer (rotated 180°
/// for a card that hangs under its target instead of sitting above it).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension AppTab {
    /// The order tabs are laid out left to right in the system tab bar,
    /// leaving out `.add` — it draws in its own trailing circle
    /// (`_UITabBarAuxiliaryView`), not a slot in the main bar's button row
    /// (confirmed by the spike: the bar holds exactly this many buttons).
    static var mainBarOrder: [AppTab] {
        var order: [AppTab] = [.home, .activity, .insights]
        if NavOption.current.hasYouTab { order.append(.you) }
        if NavOption.current.hasSearchTab { order.append(.search) }
        return order
    }
}

/// What `TabBarProbe` found, in the UIKit window's coordinate space.
/// `IntroOverlay` converts these into its own `GeometryReader`'s local
/// space via `.global`, which is the same space for a single full-screen
/// window.
struct TabBarLayout: Equatable {
    var bar: CGRect?
    var addCircle: CGRect?
    /// The main bar's own item buttons, left to right, matching
    /// `AppTab.mainBarOrder` — not `.selected`, which tracks whichever tab
    /// is currently chosen and lags an animated tab change by a frame or
    /// two.
    var items: [CGRect] = []

    var foundNothing: Bool { bar == nil && addCircle == nil && items.isEmpty }
}

/// Finds the system tab bar's frame, the separate "+" circle (the
/// `role: .prominent` / `.search` tab that draws as its own glass circle —
/// spec's "trap": a `Tab` label takes no `anchorPreference`) and each main
/// item's own frame, by walking the UIKit view hierarchy SwiftUI's
/// `TabView` is backed by.
///
/// `UITabBar` is public API and has existed unchanged for years; the other
/// class names below are private (`_UITabBarAuxiliaryView`, `_UITabButton`
/// as of iOS 26/27) and are matched by substring so a rename doesn't crash,
/// only misses. Every field is optional, and `IntroOverlay` falls back to
/// the whole bar's band when a field is nil — the spec's own fallback for
/// "the cutout misses the control".
struct TabBarProbe: UIViewRepresentable {
    @Binding var layout: TabBarLayout

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onFound = { found in
            if found != layout { layout = found }
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onFound: ((TabBarLayout) -> Void)?
        private var timer: Timer?
        private var attempts = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            timer?.invalidate()
            attempts = 0
            guard window != nil else { return }
            search()
            // SwiftUI's own layout pass — and an animated tab change — can
            // land a frame or two after this view mounts; a short poll
            // catches the settled position without a fixed, possibly too
            // short delay.
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                self.attempts += 1
                self.search()
                if self.attempts >= 10 { t.invalidate() }
            }
        }

        deinit { timer?.invalidate() }

        private func search() {
            guard let window else { return }
            var barView: UIView?
            var auxView: UIView?
            Self.find(window, barView: &barView, auxView: &auxView)
            var found = TabBarLayout()
            // `to: nil` converts into the window's own coordinate space
            // (UIKit's rule for a view with no destination view given),
            // the same space as SwiftUI's `.global` for one full-screen
            // window — the fix for the ring landing 10-20pt off target.
            if let barView { found.bar = barView.convert(barView.bounds, to: nil) }
            if let auxView { found.addCircle = auxView.convert(auxView.bounds, to: nil) }
            if let barView { found.items = Self.itemFrames(in: barView) }
            onFound?(found)
        }

        /// `UITabBar` (public) and, alongside it, `_UITabBarAuxiliaryView`
        /// (private, iOS 26/27): the separate "+" circle sits outside the
        /// bar, as a sibling, not nested inside it.
        private static func find(_ view: UIView, barView: inout UIView?, auxView: inout UIView?) {
            guard !view.isHidden else { return }
            let name = String(describing: type(of: view))
            if name == "UITabBar", barView == nil { barView = view }
            else if name.contains("TabBarAuxiliaryView"), auxView == nil { auxView = view }
            if barView != nil, auxView != nil { return }
            for sub in view.subviews { find(sub, barView: &barView, auxView: &auxView) }
        }

        /// Every `_UITabButton` frame inside `bar`, left to right, deduped
        /// (the bar draws each item's button twice at the same frame — an
        /// interaction layer over a visual one — so plain traversal order
        /// double-counts every item).
        private static func itemFrames(in bar: UIView) -> [CGRect] {
            var seen: [CGRect] = []
            collectButtons(bar, into: &seen)
            return seen.sorted { $0.minX < $1.minX }
        }

        private static func collectButtons(_ view: UIView, into frames: inout [CGRect]) {
            guard !view.isHidden else { return }
            if String(describing: type(of: view)) == "_UITabButton" {
                let frame = view.convert(view.bounds, to: nil)
                if !frames.contains(frame) { frames.append(frame) }
            }
            for sub in view.subviews { collectButtons(sub, into: &frames) }
        }
    }
}

// MARK: - Day header measurement (step `.move`)

/// Reported by `ActivityView.pagerHeader` up to whichever ancestor reads
/// `.overlayPreferenceValue(IntroDayHeaderKey.self)` — `RootView`, at the
/// same level `IntroOverlay` is placed, since `ActivityView`'s own `List` +
/// `ScrollViewReader` sits well below that.
///
/// Both frames `pagerHeader` reports, in one value: the whole row (for the
/// cutout) and the "Older Day" chevron button's own 44pt square separately
/// (for the finger) — its measured frame doesn't line up with the header
/// row's, since the chevrons hang out past it (`pagerHeader`'s negative
/// horizontal padding). Two `.preference` calls from different descendants
/// of the same `pagerHeader` each set one field; `reduce` merges them.
struct IntroDayFrames: Equatable {
    var header: CGRect? = nil
    var chevron: CGRect? = nil
}

struct IntroDayHeaderKey: PreferenceKey {
    static var defaultValue = IntroDayFrames()
    static func reduce(value: inout IntroDayFrames, nextValue: () -> IntroDayFrames) {
        let next = nextValue()
        if let header = next.header { value.header = header }
        if let chevron = next.chevron { value.chevron = chevron }
    }
}

private struct IntroWatchingDayHeaderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only while the intro's `.move` step is on screen: gates whether
    /// `ActivityView`'s day header spends a `GeometryReader` measuring
    /// itself for `IntroDayHeaderKey` — free the rest of the time.
    var introWatchingDayHeader: Bool {
        get { self[IntroWatchingDayHeaderKey.self] }
        set { self[IntroWatchingDayHeaderKey.self] = newValue }
    }
}
