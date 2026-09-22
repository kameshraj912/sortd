import SwiftUI

/// A small status line shown under the navigation title right after a
/// pull-to-refresh, instead of a custom pull spinner.
///
/// Why not a fully custom pull-down indicator: `.refreshable` hands its
/// pull gesture and progress to a system-owned control (`UIRefreshControl`
/// under SwiftUI's `List`, a system spinner under `ScrollView`) with no
/// public API to swap in custom content — anything that tried would mean
/// reaching for private UIKit internals, would behave differently between
/// Home's `ScrollView` and Activity's `List`, and could break on an iOS
/// point release. The brand's four bars are shown here instead: a brief,
/// reliable confirmation once the pull finishes, using only public API.
struct RefreshStatusLine: View {
    enum State: Equatable {
        case refreshing
        case upToDate
        case newPurchases(Int)
    }

    var state: State

    var body: some View {
        HStack(spacing: 8) {
            PulsingBrandBars(active: state == .refreshing)
            Text(text(for: state))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
    }

    private func text(for state: State) -> String {
        switch state {
        case .refreshing: "Checking for new purchases…"
        case .upToDate: "Up to date"
        case .newPurchases(let n): n == 1 ? "1 new purchase" : "\(n) new purchases"
        }
    }
}

/// The four brand bars, growing/pulsing one after another while `active`;
/// settle to a small even row once refresh is done.
private struct PulsingBrandBars: View {
    var active: Bool
    @State private var lit = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Color.brandPalette.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.brandPalette[i])
                    .frame(width: 4, height: (active && !reduceMotion && lit == i) ? 14 : 6)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeInOut(duration: 0.3), value: lit)
        .accessibilityHidden(true)
        .task(id: active) {
            guard active, !reduceMotion else { lit = -1; return }
            while !Task.isCancelled {
                for i in Color.brandPalette.indices {
                    lit = i
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
        }
    }
}
