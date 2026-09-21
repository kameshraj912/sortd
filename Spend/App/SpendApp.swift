import SwiftUI
import SwiftData

@main
struct SpendApp: App {
    /// "system", "light" or "dark". System follows the phone (Apple's advice);
    /// the other two are for people who want Spend one way always.
    @AppStorage("appearance") private var appearance = "system"

    private var scheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SPEND_APPEARANCE"] {
        case "light": return .light
        case "dark": return .dark
        default: break
        }
        #endif
        return switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    private func applyAppearance() {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["SPEND_APPEARANCE"] { Appearance.apply(forced); return }
        #endif
        Appearance.apply(appearance)
    }

    /// Early test builds linked Gmail through a Google Apps Script with a
    /// secret key. That link is gone; clear its saved key and settings once.
    private static func removeAppsScriptLink() {
        let key = "emailAccounts"
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        let list = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        for account in list {
            if let id = account["id"] as? String { Keychain.delete("email-sync-\(id)") }
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    init() {
        CrashReporting.start()
        Self.removeAppsScriptLink()
        // Share-sheet copies of the backup or CSV from a past session.
        Exports.clear()
        let context = SpendStore.container.mainContext
        let used = Set(((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).map(\.cardRaw))
        CardBook.shared.adoptLegacy(usedIds: used)
        // Only the original install (purchases on the cards the app shipped
        // with) predates setup and home currency; its values are in AUD.
        // Once only: an install from before setup existed (purchases on the
        // original card ids, and setup never finished).
        let legacy = !used.isDisjoint(with: CardInfo.legacy.map(\.id))
            && !UserDefaults.standard.bool(forKey: "legacyChecked")
            && UserDefaults.standard.object(forKey: OnboardingView.doneKey) == nil
        UserDefaults.standard.set(true, forKey: "legacyChecked")
        if legacy {
            UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
            if UserDefaults.standard.string(forKey: Money.homeKey) == nil {
                UserDefaults.standard.set("AUD", forKey: Money.homeKey)
                UserDefaults.standard.set("AUD", forKey: FXService.convertedKey)
            }
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["SPEND_DEMO"] == "1" {
            DemoData.load(in: SpendStore.container.mainContext)
            UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
        }
        if let style = env["SPEND_STYLE"] { UserDefaults.standard.set(style, forKey: "cardStyle") }
        if let budget = env["SPEND_BUDGET"].flatMap(Double.init) { UserDefaults.standard.set(budget, forKey: "monthlyBudget") }
        // Screen recordings: SPEND_REEL_TAP=<seconds> runs one real Apple Pay
        // tap through the same code the Shortcuts automation calls.
        if let delay = env["SPEND_REEL_TAP"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                _ = try? await LogPurchaseIntent.handle(merchant: "Seven Seeds Coffee", amount: "A$5.50", card: "NAB Visa Debit",
                                                        in: SpendStore.container.mainContext, book: .shared,
                                                        now: Calendar.current.date(bySettingHour: 8, minute: 12, second: 0, of: .now) ?? .now)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SPEND_GRADIENT_LAB"] == "1" {
                GradientLab()
            } else if let screen = ProcessInfo.processInfo.environment["SPEND_SCREEN"] {
                DebugScreenHost(name: screen)
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
            }
            .foregroundStyle(Color.ink)
            // Set on the windows directly: SwiftUI's preferredColorScheme
            // doesn't always repaint when going back to "System" (needed a
            // restart). The window override applies at once, sheets included.
            .onChange(of: appearance, initial: true) { applyAppearance() }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in applyAppearance() }
        }
        .modelContainer(SpendStore.container)

    }
}

enum AppTab: Hashable, CaseIterable {
    case home, activity, insights, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .activity: "list.bullet"
        case .insights: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    /// Debug: SPEND_ONBOARD_STEP opens setup even after it was finished.
    #if DEBUG
    static let forceSetup = ProcessInfo.processInfo.environment["SPEND_ONBOARD_STEP"] != nil
    #else
    static let forceSetup = false
    #endif

    @Environment(\.modelContext) private var context
    @AppStorage(OnboardingView.doneKey) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var lock = AppLock()
    @State private var router = Router.shared
    /// Set when setup finishes, so the cover closes even when a debug flag
    /// is forcing it open.
    @State private var setupFinished = false
    #if DEBUG
    @State private var tab: AppTab = .debugStart
    #else
    @State private var tab: AppTab = .home
    #endif

    private var coverState: CoverState {
        if lock.isLocked { return .locked }
        if onboarded, !Self.forceSetup, scenePhase != .active { return .cover }
        return .none
    }

    var body: some View {
        // The system tab bar is hidden and replaced with a flat one: iOS 27
        // always draws the system bar as floating Liquid Glass.
        TabView(selection: $tab) {
            Tab(value: AppTab.home) { HomeView(tab: $tab).hideSystemTabBar() }
            Tab(value: AppTab.activity) { ActivityView().hideSystemTabBar() }
            Tab(value: AppTab.insights) { ProGate(feature: .insights) { InsightsView() }.hideSystemTabBar() }
            Tab(value: AppTab.settings) { SettingsView().hideSystemTabBar() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FlatTabBar(selection: $tab)
        }
        // The tab bar stays at the bottom, under the keyboard, like the system one.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // In its own window so open sheets are covered too. The app-switcher
        // cover shows whenever Sortd isn't active, lock on or off, so the
        // snapshot never shows purchases.
        .modifier(CoverWindow(state: coverState) { state in
            if state == .locked {
                LockView(lock: lock)
            } else {
                PrivacyCover()
            }
        })
        .onChange(of: scenePhase) { _, phase in
            lock.sceneChanged(to: phase, enabled: lockEnabled, onboarded: onboarded && !Self.forceSetup)
        }
        // A tap on a widget opens the app at what the widget was showing.
        .onOpenURL { url in
            router.open(url)
            tab = router.tab
        }
        .onChange(of: router.tab) { _, new in tab = new }
        .fullScreenCover(isPresented: .constant(!setupFinished && (!onboarded || Self.forceSetup))) {
            OnboardingView { setupFinished = true }
        }
        .task(id: scenePhase) {
            // Purchases logged in the background may still need an AUD value.
            guard scenePhase == .active else { return }
            try? TransactionLogger.refreshUncategorised(in: context)
            await FXService.ensureConverted(in: context)
            #if DEBUG
            await GmailSync.syncAll(in: context, force: ProcessInfo.processInfo.environment["SPEND_GMAIL_FORCE"] == "1")
            #else
            await GmailSync.syncAll(in: context)
            #endif
            await FXService.backfill(in: context)
            let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            await Reminders.reschedule(all.recurring())
            await Reminders.checkCategoryLimits(all)
            // Leave the widget fresh numbers. Does nothing without an App Group.
            WidgetBridge.refresh(from: context)
        }
    }
}

/// Plain bottom bar: white, a hairline on top, black when selected, grey otherwise.
struct FlatTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selection == tab ? tab.symbol + (tab == .activity ? "" : ".fill") : tab.symbol)
                            .font(.system(size: 20, weight: .regular))
                            .frame(height: 24)
                        // Like the system tab bar: labels don't grow; at the
                        // largest sizes they hide and a long press shows them big.
                        if !typeSize.isAccessibilitySize {
                            Text(tab.title)
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(selection == tab ? Color.brand : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
                .accessibilityShowsLargeContentViewer {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }
        }
        .padding(.top, 6)
        .background(Color.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    func hideSystemTabBar() -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
    }
}


/// Light / Dark / System, set on the app's windows. Called from Settings the
/// moment it changes and whenever the app opens. (SwiftUI's
/// preferredColorScheme missed the change back to System until a restart.)
@MainActor
enum Appearance {
    static func apply(_ value: String) {
        let style: UIUserInterfaceStyle = switch value {
        case "light": .light
        case "dark": .dark
        default: .unspecified
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
