import SwiftUI
import UIKit

/// The dimmed, three-step overlay (`docs/specs/2026-09-25-app-intro.md`,
/// option A): the real screen behind it, a cutout that keeps the control the
/// step is about at full brightness, a card just above the tab bar with a
/// pointer toward it, and Next / Done / Skip. `RootView` drives the selected
/// tab from `tour.step`, so the highlighted control is real.
struct IntroOverlay: View {
    @Binding var tour: IntroTour
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var probe = TabBarLayout()
    @State private var pulse = false

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
                    Self.targetFrame(for: step, probe: probe, screen: proxy.size, safeBottom: proxy.safeAreaInsets.bottom)
                        .offsetBy(dx: -origin.x, dy: -origin.y),
                    to: bounds)
                let pointerX = Self.clampedPointerOffset(target: target, screenWidth: proxy.size.width)

                ZStack(alignment: .bottom) {
                    dim(cutout: target)
                    highlight(target, approximate: probe.foundNothing)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        card(step, pointerOffsetX: pointerX)
                    }
                    .padding(.horizontal, 20)
                    // The card's bottom edge lands 16pt above the target,
                    // whatever step it is — every target here is in or next
                    // to the tab bar, so the card is always bottom-anchored,
                    // never at the top of the screen.
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 8, bounds.height - target.minY + 16))
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
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(50))
                // Once out, once back, per the spec ("each animation runs
                // once... then holds") — not a repeating pulse.
                withAnimation(.easeInOut(duration: step.motionDuration / 2)) { pulse = true }
                try? await Task.sleep(for: .seconds(step.motionDuration / 2))
                withAnimation(.easeInOut(duration: step.motionDuration / 2)) { pulse = false }
            }
        }
    }

    // MARK: Dim + cutout

    /// ~55% black with `target` cut out (`.blendMode(.destinationOut)` in a
    /// `compositingGroup`), so the control itself stays at full brightness
    /// instead of dimming along with the rest of the screen. The whole
    /// layer stays tappable, cutout included, so "tap anywhere advances"
    /// still holds over the hole.
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
        .onTapGesture { onNext() }
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

    // MARK: Card

    private func card(_ step: IntroStep, pointerOffsetX: CGFloat) -> some View {
        VStack(spacing: 14) {
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
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            // A solid fill, not `.regularMaterial`: a blurred material on a
            // shape this small rendered as a soft round blob rather than a
            // crisp triangle.
            Triangle()
                .fill(Color(.systemBackground).opacity(0.9))
                .frame(width: 16, height: 8)
                .offset(x: pointerOffsetX, y: 7)
                .accessibilityHidden(true)
        }
    }

    /// Skip is a plain text button on the leading edge; Next/Done is the
    /// prominent button on the trailing edge — both at least 44pt tall.
    /// At accessibility text sizes they stack full-width instead (a
    /// `.glassProminent` capsule with no minimum width wrapped "Next" to
    /// "Nex/t" side by side).
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
    /// one, else a computed slot over the whole tab bar band (the spec's
    /// fallback when the exact control can't be measured).
    static func targetFrame(for step: IntroStep, probe: TabBarLayout, screen: CGSize, safeBottom: CGFloat) -> CGRect {
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
            return probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
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

/// A small downward-pointing triangle, for the card's pointer.
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
