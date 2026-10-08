import SwiftUI
import SwiftData
import TipKit
import UserNotifications
#if DEBUG
import OSLog
#endif

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

    init() {
        let launch = Perf.begin("launch.init")
        defer { launch.end() }
        // SpendTests hosts inside Sortd.app and shares its defaults. A few
        // tests set the home currency to AUD for as long as they run, while
        // others read `Money.home` before and after a slow await, so they saw
        // it change (3 Oct 2026). Pinned here, before any test runs, the
        // value never moves. Never set outside a test run.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UserDefaults.standard.set("AUD", forKey: Money.homeKey)
        }
        CrashReporting.start()
        // Finish any tip left unfinished, listen for new ones, load prices.
        TipJar.shared.start()
        // PostHog starts here (or logs once that it has no key and stays off).
        Analytics.start()
        // In-app tips: one new tip a day at most, in the app's own store.
        // A reset asked for last session lands before the store opens.
        TipState.applyPendingReset()
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_TIPS_NOW"] == "1" { TipState.forceNow() }
        #endif
        do {
            try Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
        } catch {
            log.error("tips: configure failed: \(error.localizedDescription)")
        }
        TipVisibility.shared.start()
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        let context = Perf.measure("launch.container") { SpendStore.container.mainContext }
        // The store could not be opened: the recovery screen runs instead of
        // the app, on an empty in-memory store. Nothing below (widgets,
        // backups, cards) may touch it.
        if SpendStore.openFailure != nil { return }
        WidgetBridge.watchSaves()
        // Back online: the pending iCloud backup, FX rates and queued account
        // deletes each try again (see `RootView`).
        Connectivity.shared.start()
        #if SORTD_ICLOUD
        CloudBackup.watchSaves()
        #endif
        // Gmail receipts were removed: delete any saved Google token and the
        // old Gmail settings, once.
        GmailCleanup.runOnce()
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
        // The aha: the first purchase a tap or a receipt logged by itself.
        // After the legacy check, which can mark setup done. An install that
        // finished setup before this existed never sees the card.
        Activation.settleExistingInstall(setupDone: UserDefaults.standard.bool(forKey: OnboardingView.doneKey))
        Activation.watchSaves()
        // One-time fix: on some installs the removed "Send a Test Tap"
        // button (spec 2026-09-25) was the only thing that ever set
        // "reached" — clear it so the Apple Pay page stops claiming it's
        // connected. Only worth the fetch when there is something to settle.
        if LogPurchaseIntent.shortcutHasReachedApp {
            let taps = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            ApplePayStatus.settleTestTap(hasRealTap: ApplePayStatus.hasRealTap(in: taps))
        }
        // iOS 26 set up with the downloaded shortcut (builds 6 to 8) can't
        // log a tap: ask once to make the automation the new way.
        if ApplePaySetupSteps.route == .automation {
            let taps = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            ApplePaySetupSteps.resetOldIOS26Setup(hasRealTap: ApplePayStatus.hasRealTap(in: taps))
        }
        // Run lines from older builds held shop names and amounts.
        LogPurchaseIntent.scrubOldRunText()
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
        // Screenshots: SPEND_NEEDS_CHECK=1 seeds one card-only Wallet tap
        // (spec 2026-09-26, failsafe #10) so the "needs a check" row and the
        // Apple Pay page's count both show right away.
        if env["SPEND_NEEDS_CHECK"] == "1" {
            Task {
                _ = try? await LogWalletTapIntent.handle("NAB Visa Debit", in: SpendStore.container.mainContext, book: .shared)
            }
        }
        // Replay hook (spec 2026-09-26, "Apple Pay logging — failsafes";
        // applepay-slice2 part 1): any of SPEND_TAP_TEXT/_MERCHANT/_AMOUNT/
        // _CARD fires one call through `LogWalletTapIntent.performAndLog`
        // — the exact path Shortcuts uses, store-can't-open fallback to
        // `TapQueue` included — after SPEND_TAP_DELAY seconds (default 1).
        // Missing fields go in as "", same as Shortcuts sends an unset
        // parameter. SPEND_TAP_REPEAT=<n> fires it n times, SPEND_TAP_GAP
        // seconds apart (default 2), to imitate two automation triggers
        // firing for the one tap (failsafe #14). Works the same way from
        // `xcrun devicectl device process launch --environment-variables`
        // on a real phone: both read `ProcessInfo.processInfo.environment`.
        // SPEND_TAP_NTITLE/_NSUBTITLE/_NBODY fill Wallet's notification
        // (iOS 27 Notification trigger, 2 Oct 2026): any one set makes it a
        // notification run, which ignores the four tap fields.
        // SPEND_TAP_NAPP is Notification › App (8 Oct 2026): "Wallet", a
        // bank's name, or unset for a shortcut from before the app field.
        let tapKeys = ["SPEND_TAP_TEXT", "SPEND_TAP_MERCHANT", "SPEND_TAP_AMOUNT", "SPEND_TAP_CARD",
                       "SPEND_TAP_NTITLE", "SPEND_TAP_NSUBTITLE", "SPEND_TAP_NBODY"]
        if tapKeys.contains(where: { env[$0] != nil }) {
            let text = env["SPEND_TAP_TEXT"] ?? ""
            let merchant = env["SPEND_TAP_MERCHANT"] ?? ""
            let amount = env["SPEND_TAP_AMOUNT"] ?? ""
            let card = env["SPEND_TAP_CARD"] ?? ""
            let notification = WalletNotification(title: env["SPEND_TAP_NTITLE"] ?? "",
                                                  subtitle: env["SPEND_TAP_NSUBTITLE"] ?? "",
                                                  body: env["SPEND_TAP_NBODY"] ?? "",
                                                  app: env["SPEND_TAP_NAPP"])
            let delay = env["SPEND_TAP_DELAY"].flatMap(Double.init) ?? 1
            let repeatCount = max(1, env["SPEND_TAP_REPEAT"].flatMap(Int.init) ?? 1)
            let gap = env["SPEND_TAP_GAP"].flatMap(Double.init) ?? 2
            let replayLog = Logger(subsystem: "page.sortd", category: "tap-replay")
            Task {
                for i in 0..<repeatCount {
                    try? await Task.sleep(for: .seconds(i == 0 ? delay : gap))
                    let r = await LogWalletTapIntent.performAndLog(transaction: text, amount: amount, merchant: merchant,
                                                                   card: card, notification: notification)
                    replayLog.log("""
                        call \(i + 1)/\(repeatCount): text="\(text, privacy: .public)" \
                        merchant="\(merchant, privacy: .public)" amount="\(amount, privacy: .public)" \
                        card="\(card, privacy: .public)" \
                        notification="\(notification.seen, privacy: .public)" -> transaction=\(r.transaction != nil, privacy: .public) \
                        merged=\(r.merged, privacy: .public) saveFailed=\(r.saveFailed, privacy: .public) \
                        dialog="\(r.message, privacy: .public)"
                        """)
                }
            }
        }
        #endif
        // No tips in the first-launch session; after the demo flag, which
        // marks setup done.
        TipState.launched(setupDone: UserDefaults.standard.bool(forKey: OnboardingView.doneKey))
    }

    var body: some Scene {
        WindowGroup {
            Group {
            if let failure = SpendStore.openFailure {
                StoreRecoveryView(failure: failure)
            } else {
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
            }
            .foregroundStyle(Color.ink)
            // Same colour as LaunchBackground (the static launch screen), so
            // there's no flash between the launch screen and the first frame.
            .background(Color.page.ignoresSafeArea())
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
    case home, activity, insights, search, you, add

    var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .insights: "Insights"
        case .search: "Search"
        case .you: "You"
        case .add: "Add"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .activity: "list.bullet"
        case .insights: "chart.bar"
        case .search: "magnifyingglass"
        case .you: "person.crop.circle"
        case .add: "plus"
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
    /// Debug: SPEND_INTRO_NOW=1 shows the app intro at once, ignoring
    /// "seen", for screenshots.
    #if DEBUG
    static let forceIntro = ProcessInfo.processInfo.environment["SPEND_INTRO_NOW"] == "1"
    #else
    static let forceIntro = false
    #endif

    @Environment(\.modelContext) private var context
    @AppStorage(OnboardingView.doneKey) private var onboarded = false
    /// "Run Setup Again": setup shows over the app, but it stays set up
    /// (so App Lock and the privacy cover keep working).
    @AppStorage(SetupProfile.rerunKey) private var rerun = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var lock = AppLock()
    @State private var router = Router.shared
    /// Set when setup finishes, so the cover closes even when a debug flag
    /// is forcing it open.
    @State private var setupFinished = false
    @State private var showingAdd = false
    /// The Add sheet opens straight into the receipt scanner (the widget's
    /// and the + menu's Scan, `sortd://scan`).
    @State private var addStartsScanning = false
    /// When setup closed: a second tap from a double-tap on setup's last
    /// button mustn't land on the tab bar underneath.
    @State private var setupClosedAt: Date = .distantPast
    @State private var searchQuery = ""
    /// The app intro (docs/specs/2026-09-25-app-intro.md), seeded from the
    /// "seen" flag so a `RootView` made mid-session (a preview, a test)
    /// doesn't show it again.
    @State private var intro = IntroTour(seen: UserDefaults.standard.bool(forKey: IntroTour.seenKey))
    private let layout = NavLayout.current
    private let nav = NavOption.current
    #if DEBUG
    @State private var tab: AppTab = .debugStart
    #else
    @State private var tab: AppTab = .home
    #endif

    /// `ApplePayStepNudge.update` with what the store says right now.
    private func scheduleApplePayNudge() {
        let defaults = UserDefaults.standard
        // Someone who pays cash, or said they don't use Apple Pay, is never reminded.
        let wants = defaults.string(forKey: SetupProfile.paymentKey) != SetupProfile.Payment.cash.rawValue
            && !defaults.bool(forKey: ApplePayStepNudge.noApplePayKey)
        let done = onboarded && !setupPresented
        guard done, wants else { ApplePayStepNudge.cancel(); return }
        // A store that can't be read says nothing about logging: no reminder.
        guard let taps = try? context.fetch(FetchDescriptor<Transaction>()) else { return }
        let status = ApplePayStatus.resolve(lastReachedAt: LogPurchaseIntent.lastTapReceivedAt, taps: taps)
        let built = defaults.bool(forKey: ApplePaySetupSteps.automationBuiltKey)
        Task { await ApplePayStepNudge.update(status: status, saysBuilt: built, setupDone: true, wantsApplePay: true) }
    }

    /// Setup is on screen (first run, "Run Setup Again", or a debug flag).
    private var setupPresented: Bool {
        !setupFinished && (!onboarded || rerun || Self.forceSetup)
    }

    private var coverState: CoverState {
        if lock.isLocked { return .locked }
        // Not behind iOS's own permission alerts (they make the scene
        // inactive for a moment; the app isn't going anywhere).
        if onboarded, !Self.forceSetup, scenePhase != .active,
           !(scenePhase == .inactive && SystemPrompt.shared.active) { return .cover }
        return .none
    }

    var body: some View {
        // The system Liquid Glass tab bar. Settings is a sheet from the gear
        // on Home (tabs are for places people go often), and Search gets the
        // trailing search tab, as the HIG suggests.
        Group {
            // First launch: nothing behind setup, so Home doesn't flash for
            // a moment before the setup cover slides up.
            if !onboarded, !setupFinished {
                Color.page.ignoresSafeArea()
            } else {
                tabs
            }
        }
            .tint(Color.brand)
            // Cheap the rest of the time: `ActivityView`'s first row only
            // spends a `GeometryReader` measuring itself for the intro's
            // `.swipe` cutout while this is true.
            .environment(\.introWatchingFirstRow, intro.step == .swipe)
            .tabBarMinimizeBehavior(.onScrollDown)
            .modifier(RootSearch(enabled: layout.rootSearch, query: $searchQuery))
            .overlay(alignment: .bottomTrailing) {
                if layout == .fab, tab == .home || tab == .activity {
                    AddFAB(add: { showingAdd = true },
                           scan: { addStartsScanning = true; showingAdd = true },
                           importing: { router.open(URL(string: "sortd://import")!) })
                        .padding(.trailing, 20)
                        .padding(.bottom, 72)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Settings sits top-right in each tab's own navigation bar
            // (`SettingsToolbarButton`), not floated over the tabs: floated,
            // it landed on Activity's search field and drifted as lists scrolled.

            // Keep the Router in step with taps on the tab bar, so a link to
            // the tab you left (a check-in, a widget) still switches back.
            .onChange(of: tab, initial: true) { _, new in
                if router.tab != new { router.tab = new }
                // Which tabs get used, the first one at launch included. The +
                // slot never becomes `tab`.
                Analytics.shared.track(.tabOpened, ["tab": .string(new.title.lowercased())])
                // A tip visit: a tab opened, not a return from a pushed row.
                if !setupPresented { TipState.visited(new) }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { addStartsScanning = false }) {
                AddTransactionView(startsScanning: addStartsScanning)
            }
        .feedback(.select, trigger: tab)
        // The + never assigns `tab`, so the app's main action was the
        // one tab that gave no feedback at all.
        .feedback(.select, trigger: showingAdd) { _, open in open }
        .sheet(isPresented: $router.showingSettings, onDismiss: {
            // Next time Settings opens on its main list, not a page a link pushed.
            router.settingsPath = []
            // "Run Setup Again" waits for Settings to finish closing.
            if router.pendingRerun {
                router.pendingRerun = false
                rerun = true
            }
        }) { SettingsView() }
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
            // Coming back to the app on a tab is a visit to it.
            if phase == .active, !setupPresented { TipState.visited(tab) }
            #if SORTD_ICLOUD
            // Leaving the app is the natural moment to back up what was done.
            if phase == .background { CloudBackup.shared.backUpOnBackground(from: context) }
            #endif
            // And to set the reminder to finish Apple Pay logging; coming
            // back takes it down, so it always counts from the last leave.
            if phase == .background { scheduleApplePayNudge() }
            if phase == .active { ApplePayStepNudge.cancel() }
        }
        // Offline to online: the work that waited for a connection carries on.
        .onChange(of: Connectivity.shared.isOnline) { old, new in
            guard Connectivity.isReconnect(from: old, to: new), scenePhase == .active else { return }
            Task { await Connectivity.catchUp(in: context) }
        }
        // A tap on a widget opens the app at what the widget was showing.
        .onOpenURL { url in
            router.open(url)
            tab = router.tab
        }
        .onChange(of: router.tab) { _, new in if tab != new { tab = new } }
        // Widget, Siri and notification "add" and "scan" links: the one add sheet.
        .onChange(of: router.sheet, initial: true) { _, pending in
            guard pending == .add || pending == .scan else { return }
            addStartsScanning = pending == .scan
            showingAdd = true
            router.clearSheet()
        }
        // "Clear" on the sample-data banner sets onboarded back to false:
        // open setup again straight away, not on the next launch.
        .onChange(of: onboarded) { _, done in if !done { setupFinished = false } }
        .onChange(of: rerun) { _, again in if again { setupFinished = false } }
        .fullScreenCover(isPresented: .constant(setupPresented)) {
            OnboardingView {
                setupClosedAt = .now
                setupFinished = true
            }
        }
        // No tips while setup is up; the screens behind it re-check when it
        // closes, and the tab it closed onto counts as visited then.
        .onChange(of: setupPresented, initial: true) { _, showing in TipState.setupShowing = showing }
        .onChange(of: setupPresented) { _, showing in if !showing { TipState.visited(tab) } }
        // The intro: once right after setup closes, and once for an
        // existing install (the `initial: true` check fires at launch,
        // where `setupPresented` is already false). Never while setup,
        // App Lock or a sheet is up.
        .onChange(of: setupPresented, initial: true) { _, showing in if !showing { startIntroIfEligible() } }
        // An existing install with App Lock on is locked at cold launch:
        // the check above misses it, so try again once it unlocks.
        .onChange(of: lock.isLocked) { _, locked in if !locked { startIntroIfEligible() } }
        // Same idea: a sheet up at the eligible moment just delays it.
        .onChange(of: router.showingSettings) { _, showing in if !showing { startIntroIfEligible() } }
        .onChange(of: showingAdd) { _, showing in if !showing { startIntroIfEligible() } }
        .onChange(of: router.pendingIntroReplay) { _, pending in
            guard pending else { return }
            router.pendingIntroReplay = false
            intro.replay()
        }
        .onChange(of: intro, initial: true) { old, new in
            TipState.introShowing = new.step != nil
            UserDefaults.standard.set(new.seen, forKey: IntroTour.seenKey)
            if let step = new.step {
                if tab != step.tab { tab = step.tab }
                if old.step == nil { Analytics.shared.track(.introShown) }
            }
            if new.finished, !old.finished {
                // Done or Skip both end back on Home — the tour's own
                // `.tab` already says `.home` once it isn't running, but
                // nothing above sets this view's real `tab` back to it.
                tab = .home
                Analytics.shared.track(.introFinished, ["skipped": .bool(new.skipped),
                                                         "step": .int((old.step ?? .swipe).rawValue),
                                                         "auto": .bool(new.auto)])
            }
        }
        // Everything behind the intro is unreachable while it's up; the
        // overlay itself carries its own accessibility elements.
        .accessibilityHidden(introShowing)
        // Activity's first row's frame comes from `ActivityView.row`, well
        // below this in a `List` — read here via `.overlayPreferenceValue`
        // rather than `.overlay`, the only way it reaches this level.
        .overlayPreferenceValue(IntroFirstRowKey.self) { firstRow in
            if introShowing {
                IntroOverlay(tour: $intro, firstRowFrame: firstRow,
                             onNext: { intro.next() },
                             onTimeout: { intro.advanceOnTimeout() },
                             onSkip: { intro.skip() })
            }
        }
        .task(id: scenePhase) {
            // Purchases logged in the background may still need an AUD value.
            guard scenePhase == .active else { return }
            Perf.markFirstActive()
            let pass = Perf.begin("launch.activeTasks")
            defer { pass.end() }
            // Not needed for anything on screen: don't make the rest wait.
            Task { await GoogleAuth.retryPendingRevokes() }
            #if SORTD_SIGNIN
            // A withdrawn Sign in with Apple, and account deletes that
            // couldn't reach the provider or the Worker last time.
            Task {
                await AccountStore.shared.checkCredentialAtLaunch()
                await AccountStore.shared.retryPendingDeletes()
            }
            #endif
            #if SORTD_ICLOUD
            // A Delete All Data that couldn't reach iCloud last time.
            Task { await CloudBackup.shared.retryPendingDelete() }
            #endif
            // Bill reminders asked for during setup and still pending.
            SetupProfile.applyPendingBillReminders()
            Perf.measure("launch.recategorise") {
                do { try TransactionLogger.refreshUncategorised(in: context) } catch {
                    ErrorLog.report(error, where: "Launch.recategorise")
                }
            }
            // A tap Sortd couldn't save last time (spec 2026-09-26, failsafe
            // #8/#9): replay it now, at launch and every time the app comes
            // back to the foreground, not just once.
            await TapQueue.replay(in: context)
            await FXService.ensureConverted(in: context)
            await FXService.backfill(in: context)
            let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            await Reminders.reschedule(all.recurring())
            await Reminders.checkCategoryLimits(all)
            await Reminders.checkBudgetPace(all, budget: UserDefaults.standard.double(forKey: FXService.budgetKey))
            // Leave the widget fresh numbers. Does nothing without an App Group.
            WidgetBridge.refresh(from: context)
        }
    }
}


extension RootView {
    var introShowing: Bool { intro.step != nil }

    /// Starts the intro if it's eligible and nothing else is on screen:
    /// setup, App Lock and the add or Settings sheets all win.
    func startIntroIfEligible() {
        guard intro.step == nil, !showingAdd, !router.showingSettings else { return }
        // SpendTests hosts inside Sortd.app, so the real app (and this
        // view) genuinely launches for unit tests too. The intro must not
        // start there: `TipState.introShowing` is a global the pure-logic
        // tests depend on staying false with nothing to reset it.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if Self.forceIntro {
            intro.start()
            #if DEBUG
            // Screenshots: SPEND_INTRO_STEP=1 or 2 jumps straight to that
            // step (0 is the default from start()).
            if let n = Int(ProcessInfo.processInfo.environment["SPEND_INTRO_STEP"] ?? "") {
                for _ in 0..<max(0, min(n, IntroTour.steps.count - 1)) { intro.next() }
            }
            #endif
            return
        }
        guard intro.shouldShow(setupDone: onboarded, setupShowing: setupPresented, locked: lock.isLocked) else { return }
        // Begins 0.6s after Home settles, and only once the setup sheet is
        // fully gone (the eligibility check above already passed once) —
        // something else, like the add sheet, can still open in that
        // window, so every guard is re-read after the sleep, not just
        // before it.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard intro.step == nil, !showingAdd, !router.showingSettings else { return }
            guard intro.shouldShow(setupDone: onboarded, setupShowing: setupPresented, locked: lock.isLocked) else { return }
            intro.start()
        }
    }

    /// The tab bar's selection. The + slot is an action, not a place: picking
    /// it opens the add sheet and the current tab stays put (no flash of an
    /// empty tab, one haptic).
    var tabSelection: Binding<AppTab> {
        Binding(get: { tab }, set: { new in
            guard Date.now.timeIntervalSince(setupClosedAt) > 0.6 else { return }
            if new == .add { showingAdd = true } else { tab = new }
        })
    }

    @ViewBuilder
    var tabs: some View {
        // The prominent tab is in the iOS 27 SDK only, so the code is compiled
        // in only by Xcode 27 (Swift 6.4). Older Xcode — and iOS 26 at run
        // time — uses the search-role slot below, which looks the same.
        #if compiler(>=6.4)
        if layout == .prominent, #available(iOS 27, *) {
            TabView(selection: tabSelection) {
                Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) { HomeView(tab: $tab) }
                Tab(AppTab.activity.title, systemImage: AppTab.activity.symbol, value: AppTab.activity) { ActivityView() }
                Tab(AppTab.add.title, systemImage: AppTab.add.symbol, value: AppTab.add, role: .prominent) { Color.clear }
                Tab(AppTab.insights.title, systemImage: AppTab.insights.symbol, value: AppTab.insights) { InsightsView() }
                if nav.hasYouTab {
                    Tab(AppTab.you.title, systemImage: AppTab.you.symbol, value: AppTab.you) { SettingsView() }
                }
                if nav.hasSearchTab {
                    Tab(value: AppTab.search, role: .search) { SearchView() }
                }
            }
        } else if layout == .prominent {
            legacyPlusTabs
        } else {
            searchTabOnlyTabs
        }
        #else
        if layout == .prominent {
            legacyPlusTabs
        } else {
            searchTabOnlyTabs
        }
        #endif
    }

    /// iOS 26, and any Xcode older than 27: iOS 26 draws the search-role tab
    /// as the same separate glass circle, so + goes in that slot and Search
    /// sits inside the bar. The same look as iOS 27's prominent tab. Tapping
    /// + never shows this tab; the selection binding opens the add sheet.
    var legacyPlusTabs: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) { HomeView(tab: $tab) }
            Tab(AppTab.activity.title, systemImage: AppTab.activity.symbol, value: AppTab.activity) { ActivityView() }
            Tab(AppTab.insights.title, systemImage: AppTab.insights.symbol, value: AppTab.insights) { InsightsView() }
            if nav.hasYouTab {
                Tab(AppTab.you.title, systemImage: AppTab.you.symbol, value: AppTab.you) { SettingsView() }
            }
            if nav.hasSearchTab {
                Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search) { SearchView() }
            }
            Tab(AppTab.add.title, systemImage: AppTab.add.symbol, value: AppTab.add, role: .search) { Color.clear }
        }
    }

    /// The other nav layouts (no + circle): Search keeps the system slot.
    var searchTabOnlyTabs: some View {
        TabView(selection: tabSelection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) { HomeView(tab: $tab) }
            Tab(AppTab.activity.title, systemImage: AppTab.activity.symbol, value: AppTab.activity) { ActivityView() }
            Tab(AppTab.insights.title, systemImage: AppTab.insights.symbol, value: AppTab.insights) { InsightsView() }
            Tab(value: AppTab.search, role: .search) {
                SearchView(external: layout.rootSearch ? $searchQuery : nil)
            }
        }
    }
}

private struct RootSearch: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "Shop, category or note")
        } else {
            content
        }
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
