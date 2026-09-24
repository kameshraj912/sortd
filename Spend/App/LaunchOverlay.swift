import SwiftUI

/// The cold-start-only handoff from the native launch screen (`Spend-Info.plist`'s
/// `UILaunchScreen`, which shows the `LaunchWordmark` image on `LaunchBackground`,
/// statically — UIKit can't animate that screen) to a SwiftUI overlay that looks
/// identical on its first frame, then grows the brand bar in under the wordmark
/// and fades away.
///
/// Its first frame must be pixel-for-pixel the static launch screen: same
/// `LaunchWordmark` image, same `Color.page` background, same centring
/// (`UIImageRespectsSafeAreaInsets` is on, so the launch screen centres the
/// image within the safe area — this view does the same by not extending its
/// content past the safe area, only the background). The bar isn't baked into
/// `LaunchWordmark`; it's drawn here in SwiftUI, starting at zero width, so
/// there's nothing to swap out or jump when the animation begins.
///
/// `SpendApp` shows this once per process launch (its `@State` starts `true`
/// and only ever goes to `false`), so it never replays on a return from
/// background. It sits inside the main window as a plain overlay — the App
/// Lock cover and onboarding's full-screen cover both present above it (a
/// separate `UIWindow` at `.alert + 1`, and a UIKit modal presentation,
/// respectively, both of which cover the whole window), so neither is
/// blocked or delayed by it. On a first-ever launch (not onboarded yet) the
/// onboarding cover presents immediately and hides this overlay for its
/// whole ~0.75s, which is fine — it only ever needs to be seen on a normal
/// cold start into the app itself.
struct LaunchOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    @State private var barGrown = [Bool](repeating: false, count: 4)
    @State private var fading = false

    private struct Bar {
        let width: CGFloat
        let color: Color
    }

    // Brand bar spec (Brand/README.md): 5pt tall pills, 5pt gaps, 9pt below
    // the wordmark, widths 34/26/20/14pt, brand colours, centred.
    private static let bars: [Bar] = [
        Bar(width: 34, color: Color(red: 0xF0 / 255, green: 0x64 / 255, blue: 0x3D / 255)),
        Bar(width: 26, color: Color(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255)),
        Bar(width: 20, color: Color(red: 0x7B / 255, green: 0x6B / 255, blue: 0xF0 / 255)),
        Bar(width: 14, color: Color(red: 0x2B / 255, green: 0xB0 / 255, blue: 0x7A / 255)),
    ]
    private static let barHeight: CGFloat = 5
    private static let barGap: CGFloat = 5
    private static let gapBelowWordmark: CGFloat = 9
    private static let totalBarWidth = bars.reduce(0) { $0 + $1.width } + barGap * CGFloat(bars.count - 1)
    /// Fixed leading offset for each bar, from the final (fully-grown) layout,
    /// so growing a bar's width never shifts its neighbours.
    private static let barOffsets: [CGFloat] = {
        var offsets: [CGFloat] = []
        var x: CGFloat = 0
        for bar in bars {
            offsets.append(x)
            x += bar.width + barGap
        }
        return offsets
    }()

    /// A beat before the bars start growing, so this animation's own
    /// transaction doesn't get folded into the system's still-in-flight
    /// launch transition (see `start()`). Bars then grow over ~0.5s total
    /// (staggered), then a ~0.25s fade — the whole thing lands at the 0.8s
    /// budget.
    private static let preBuffer = 0.05
    private static let growDuration = 0.35
    private static let stagger = 0.05
    private static let fadeDuration = 0.25
    private static var growTotalDuration: Double { stagger * Double(bars.count - 1) + growDuration }

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            VStack(spacing: Self.gapBelowWordmark) {
                Image("LaunchWordmark")
                if !reduceMotion {
                    barsRow
                }
            }
        }
        .opacity(fading ? 0 : 1)
        .allowsHitTesting(!fading)
        .onAppear(perform: start)
    }

    private var barsRow: some View {
        ZStack(alignment: .leading) {
            ForEach(Self.bars.indices, id: \.self) { i in
                Capsule()
                    .fill(Self.bars[i].color)
                    .frame(width: barGrown[i] ? Self.bars[i].width : 0, height: Self.barHeight)
                    .offset(x: Self.barOffsets[i])
            }
        }
        .frame(width: Self.totalBarWidth, height: Self.barHeight, alignment: .leading)
    }

    private func start() {
        guard isPresented else { return }
        if reduceMotion {
            // No bar growth to watch, so no reason to hold the launch frame:
            // fade straight to the real app.
            dismiss(after: Self.fadeDuration)
            return
        }
        // Each bar's own explicit, separately-scheduled `withAnimation` call
        // (rather than one shared implicit `.animation(value:).delay()`),
        // after `preBuffer`: `onAppear` fires while the system's own
        // launch-transition transaction is still in flight, which can fold
        // an animation started right then into that transaction and apply
        // it instantly instead of animating it.
        for i in Self.bars.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.preBuffer + Double(i) * Self.stagger) {
                withAnimation(.easeOut(duration: Self.growDuration)) { barGrown[i] = true }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.preBuffer + Self.growTotalDuration) {
            dismiss(after: Self.fadeDuration)
        }
    }

    private func dismiss(after fadeDuration: Double) {
        withAnimation(.easeInOut(duration: fadeDuration)) { fading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { isPresented = false }
    }
}
