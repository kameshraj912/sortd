import SwiftUI
import UIKit

/// The dimmed, three-step overlay (`docs/specs/2026-09-25-app-intro.md`,
/// option A): the real screen behind it, a highlight on the control the step
/// is about, one short line, and Next / Done / Skip. `RootView` drives the
/// selected tab from `tour.step`, so the highlighted control is real.
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
            GeometryReader { proxy in
                let target = Self.targetFrame(for: step, probe: probe, screen: proxy.size,
                                              safeBottom: proxy.safeAreaInsets.bottom)
                ZStack(alignment: .top) {
                    // ~55% black, the whole screen. Tapping it (outside the
                    // card's own buttons) advances, per the spec.
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { onNext() }
                    highlight(target, approximate: probe.foundNothing)
                    card(step)
                        .padding(.top, proxy.safeAreaInsets.top + 12)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                // One step to the next always fades (Reduce Motion or not —
                // the spec reserves sliding for the setup and month
                // transitions elsewhere); appearing the first time and
                // Next/Skip both go through this same `.id`.
                .id(step)
                .transition(.opacity)
            }
            .background(TabBarProbe(layout: $probe))
            .accessibilityElement(children: .contain)
            .task(id: step) {
                pulse = false
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeInOut(duration: step.motionDuration)) { pulse = true }
            }
        }
    }

    // MARK: Highlight

    @ViewBuilder
    private func highlight(_ frame: CGRect, approximate: Bool) -> some View {
        if frame != .zero {
            RoundedRectangle(cornerRadius: min(frame.width, frame.height) / 2, style: .continuous)
                .strokeBorder(Color.brand, lineWidth: 3)
                .background {
                    RoundedRectangle(cornerRadius: min(frame.width, frame.height) / 2, style: .continuous)
                        .fill(Color.brand.opacity(0.18))
                }
                .frame(width: frame.width + 14, height: frame.height + 14)
                .position(x: frame.midX, y: frame.midY)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.06 : 1))
                .shadow(color: Color.brand.opacity(reduceMotion ? 0.5 : (pulse ? 0.7 : 0.3)), radius: 14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if approximate {
                Image(systemName: "arrow.down")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.brand)
                    .position(x: frame.midX, y: max(0, frame.minY - 22))
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Card

    private func card(_ step: IntroStep) -> some View {
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
    }

    /// Side by side normally; at accessibility text sizes a `.glassProminent`
    /// capsule with no minimum width was squashed round and "Next" wrapped
    /// to "Nex/t" — full-width, stacked buttons instead (same idea as
    /// `SpendChart.rangeChips`'s layout switch).
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
            .buttonStyle(.glass)
            .tint(Color.ink)
    }

    private func nextButton(_ step: IntroStep) -> some View {
        Button(step == .move ? "Done" : "Next", action: onNext)
            .buttonStyle(.glassProminent)
            .tint(Color.brand)
            // The window sets `.foregroundStyle(Color.ink)` further up
            // (`SpendApp`); without this, the label drew ink on ink.
            .foregroundStyle(Color.onBrand)
        .frame(maxWidth: 360)
    }

    // MARK: Target frame

    /// Where to draw the highlight: the probe's live UIKit frame when it
    /// found one, else a computed slot over the whole tab bar band (the
    /// spec's fallback when the exact control can't be measured).
    static func targetFrame(for step: IntroStep, probe: TabBarLayout, screen: CGSize, safeBottom: CGFloat) -> CGRect {
        switch step {
        case .add:
            return probe.addCircle ?? probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
        case .insights:
            return probe.selected ?? probe.bar ?? fallbackBand(screen: screen, safeBottom: safeBottom)
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
}

/// What `TabBarProbe` found, in its own view's coordinate space (which
/// `IntroOverlay` sizes to the full screen, so the frames line up with its
/// own `GeometryReader`).
struct TabBarLayout: Equatable {
    var bar: CGRect?
    var addCircle: CGRect?
    var selected: CGRect?

    var foundNothing: Bool { bar == nil && addCircle == nil && selected == nil }
}

/// Finds the system tab bar's frame, the separate "+" circle (the
/// `role: .prominent` / `.search` tab that draws as its own glass circle —
/// spec's "trap": a `Tab` label takes no `anchorPreference`) and the
/// currently selected item's frame, by walking the UIKit view hierarchy
/// SwiftUI's `TabView` is backed by.
///
/// `UITabBar` is public API and has existed unchanged for years; the other
/// two class names are private (`_UITabBarAuxiliaryView`,
/// `_UITabSelectionView` as of iOS 26/27) and are matched by substring so a
/// rename doesn't crash, only misses. Every field is optional, and
/// `IntroOverlay` falls back to the whole bar's band when a field is nil —
/// the spec's own fallback for "the cutout misses the control".
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
            // SwiftUI's own layout pass can land a frame or two after this
            // view mounts; a short poll catches the real position without a
            // fixed, possibly-too-short delay.
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
            var found = TabBarLayout()
            Self.walk(window, into: &found, target: self)
            onFound?(found)
        }

        private static func walk(_ view: UIView, into found: inout TabBarLayout, target: UIView) {
            let name = String(describing: type(of: view))
            if name == "UITabBar", found.bar == nil {
                found.bar = view.convert(view.bounds, to: target)
            } else if name.contains("TabBarAuxiliaryView"), found.addCircle == nil {
                found.addCircle = view.convert(view.bounds, to: target)
            } else if name.contains("TabSelectionView"), found.selected == nil {
                found.selected = view.convert(view.bounds, to: target)
            }
            for sub in view.subviews { walk(sub, into: &found, target: target) }
        }
    }
}
