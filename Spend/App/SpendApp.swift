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
    init() {
        let context = SpendStore.container.mainContext
        let used = Set(((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).map(\.cardRaw))
        CardBook.shared.adoptLegacy(usedIds: used)
        // Only the original install (purchases on the cards the app shipped
        // with) predates setup and home currency; its values are in AUD.
        let legacy = !used.isDisjoint(with: CardInfo.legacy.map(\.id))
        if legacy {
            UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
            if UserDefaults.standard.string(forKey: Money.homeKey) == nil {
                UserDefaults.standard.set("AUD", forKey: Money.homeKey)
                UserDefaults.standard.set("AUD", forKey: FXService.convertedKey)
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_SAMPLE_DATA"] == "1" {
            SampleData.load(into: SpendStore.container.mainContext)
        }
        let env = ProcessInfo.processInfo.environment
        if env["SPEND_DEMO"] == "1" {
            DemoData.load(in: SpendStore.container.mainContext)
            UserDefaults.standard.set(true, forKey: OnboardingView.doneKey)
        }
        if let style = env["SPEND_STYLE"] { UserDefaults.standard.set(style, forKey: "cardStyle") }
        if let paths = ProcessInfo.processInfo.environment["SPEND_IMPORT_JSON"] {
            SampleData.importJSON(paths.split(separator: ":").map(String.init),
                                  into: SpendStore.container.mainContext)
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
            .preferredColorScheme(scheme)
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
    #if DEBUG
    @State private var tab: AppTab = .debugStart
    #else
    @State private var tab: AppTab = .home
    #endif

    var body: some View {
        // The system tab bar is hidden and replaced with a flat one: iOS 27
        // always draws the system bar as floating Liquid Glass.
        TabView(selection: $tab) {
            Tab(value: AppTab.home) { HomeView(tab: $tab).hideSystemTabBar() }
            Tab(value: AppTab.activity) { ActivityView().hideSystemTabBar() }
            Tab(value: AppTab.insights) { InsightsView().hideSystemTabBar() }
            Tab(value: AppTab.settings) { SettingsView().hideSystemTabBar() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FlatTabBar(selection: $tab)
        }
        // The tab bar stays at the bottom, under the keyboard, like the system one.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: .constant(!onboarded || Self.forceSetup)) {
            OnboardingView()
        }
        .task(id: scenePhase) {
            // Purchases logged in the background may still need an AUD value.
            guard scenePhase == .active else { return }
            try? TransactionLogger.refreshUncategorised(in: context)
            await FXService.ensureConverted(in: context)
            await EmailSync.syncAll(in: context)
            #if DEBUG
            await GmailSync.syncAll(in: context, force: ProcessInfo.processInfo.environment["SPEND_GMAIL_FORCE"] == "1")
            #else
            await GmailSync.syncAll(in: context)
            #endif
            await FXService.backfill(in: context)
            let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            await Reminders.reschedule(all.recurring())
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
