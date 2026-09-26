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
                Text(buttonTitle).primaryPill(enabled: !lock.authenticating)
            }
            .primaryGlass()
            .disabled(lock.authenticating)
            .padding(.horizontal, 24)
            if usesBiometrics {
                Text("Or use your iPhone passcode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.page.ignoresSafeArea())
        .task(id: scenePhase) {
            // Prompt only once, and only when the app is on screen.
            guard scenePhase == .active, !prompted else { return }
            prompted = true
            await lock.unlock()
        }
    }

    /// No biometry enrolled (or none on the device): the system sheet only
    /// offers the passcode, so the button says "Unlock" plainly.
    private var usesBiometrics: Bool { AppLock.methodName != "Passcode" }

    private var buttonTitle: String {
        usesBiometrics ? "Unlock with \(AppLock.methodName)" : "Unlock"
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

/// What the cover window shows.
enum CoverState: Equatable {
    case none, cover, locked
}

/// Shows the lock or the app-switcher cover in its own window, above every
/// sheet, alert and full-screen cover the app presents. A plain overlay sits
/// under sheets, so an open Add or Budget sheet would show in the app switcher
/// and stay usable behind the lock.
struct CoverWindow<Cover: View>: ViewModifier {
    let state: CoverState
    @ViewBuilder let cover: (CoverState) -> Cover
    @State private var window: UIWindow?

    func body(content: Content) -> some View {
        content.onChange(of: state, initial: true) { _, new in update(new) }
    }

    private func update(_ state: CoverState) {
        guard state != .none else {
            // Hidden windows take no touches, so the app works normally underneath.
            window?.isHidden = true
            return
        }
        let w = window ?? make()
        (w?.rootViewController as? UIHostingController<AnyView>)?.rootView = AnyView(cover(state))
        w?.isHidden = false
    }

    private func make() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.overrideUserInterfaceStyle = scene.windows.first?.overrideUserInterfaceStyle ?? .unspecified
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        window = w
        return w
    }
}
