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
        let launch = Perf.begin("launch.init")
        defer { launch.end() }
        CrashReporting.start()
        let context = Perf.measure("launch.container") { SpendStore.container.mainContext }
        WidgetBridge.watchSaves()
        Self.removeAppsScriptLink()
        // Share-sheet copies of the backup or CSV from a past session.
        Exports.clear()
        // Only the card column: this runs before the first frame.
        var cardsOnly = FetchDescriptor<Transaction>()
        cardsOnly.propertiesToFetch = [\.cardRaw]
        let used = Perf.measure("launch.cardScan") { Set(((try? context.fetch(cardsOnly)) ?? []).map(\.cardRaw)) }
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
    /// The flat tab bar's height. The TabView doesn't pass the bar's
    /// safe-area inset on to its tabs, so without this the last row of
    /// every list stayed under the bar. Handed down as `tabBarClearance`.
    @State private var tabBarHeight: CGFloat = 0
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
            Tab(value: AppTab.home) { HomeView(tab: $tab).hideSystemTabBar(clearing: tabBarHeight) }
            Tab(value: AppTab.activity) { ActivityView().hideSystemTabBar(clearing: tabBarHeight) }
            Tab(value: AppTab.insights) { ProGate(feature: .insights) { InsightsView() }.hideSystemTabBar(clearing: tabBarHeight) }
            Tab(value: AppTab.settings) { SettingsView().hideSystemTabBar(clearing: tabBarHeight) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FlatTabBar(selection: $tab)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
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
        // "Clear" on the sample-data banner sets onboarded back to false:
        // open setup again straight away, not on the next launch.
        .onChange(of: onboarded) { _, done in if !done { setupFinished = false } }
        .fullScreenCover(isPresented: .constant(!setupFinished && (!onboarded || Self.forceSetup))) {
            OnboardingView { setupFinished = true }
        }
        .task(id: scenePhase) {
            // Purchases logged in the background may still need an AUD value.
            guard scenePhase == .active else { return }
            Perf.markFirstActive()
            let pass = Perf.begin("launch.activeTasks")
            defer { pass.end() }
            // Not needed for anything on screen: don't make the rest wait.
            Task { await GoogleAuth.retryPendingRevokes() }
            // A subscription can expire while the app sits in memory, and
            // expiry sends no update: check again before anything uses isPro.
            await Perf.measure("launch.proRefresh") { await ProStore.shared.refresh() }
            Perf.measure("launch.recategorise") { try? TransactionLogger.refreshUncategorised(in: context) }
            // Gmail, FX and the widget: the same pass pull-to-refresh runs on
            // Home and Activity. Routing both through RefreshCoordinator means
            // a pull that lands while this scene-phase sync is still running
            // (or the other way around) awaits the one already in flight
            // instead of starting a second one.
            #if DEBUG
            await RefreshCoordinator.refresh(in: context, force: ProcessInfo.processInfo.environment["SPEND_GMAIL_FORCE"] == "1")
            #else
            await RefreshCoordinator.refresh(in: context)
            #endif
            let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            await Reminders.reschedule(all.recurring())
            await Reminders.checkCategoryLimits(all)
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
    /// Hides the system bar, and tells the pages in this tab how tall the
    /// flat one is (see `clearsTabBar()`).
    func hideSystemTabBar(clearing barHeight: CGFloat) -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
            .environment(\.tabBarClearance, barHeight)
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
