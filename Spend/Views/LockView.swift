import SwiftUI

/// Full-screen lock. Asks for Face ID once when shown; the button asks again.
struct LockView: View {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            LockBadge()
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Text("Unlock").primaryPill(enabled: !lock.authenticating)
            }
            .buttonStyle(.plain)
            .disabled(lock.authenticating)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.page.ignoresSafeArea())
        .task(id: scenePhase) {
            // Prompt only once, and only when the app is on screen.
            guard scenePhase == .active, !prompted else { return }
            prompted = true
            await lock.unlock()
        }
    }
}

/// Plain cover for the app switcher, so purchases don't show in the snapshot.
struct PrivacyCover: View {
    var body: some View {
        LockBadge(showsTitle: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.page.ignoresSafeArea())
    }
}

private struct LockBadge: View {
    var showsTitle = true

    var body: some View {
        VStack(spacing: 16) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 15, style: .continuous))
                .accessibilityHidden(true)
            if showsTitle {
                Text("Sortd is locked")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }
            BrandBar()
        }
    }
}
