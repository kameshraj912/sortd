import SwiftUI

/// The one empty-screen look for the whole app: a plain symbol, a headline,
/// one short line, and optional buttons. Same text styles as everywhere else
/// (Apple's ContentUnavailableView uses bigger type than the rest of Sortd).
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, symbol: String, message: String,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) { actions() }
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
