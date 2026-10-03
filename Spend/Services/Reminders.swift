import Foundation
import Observation
import UserNotifications

/// True while a system sheet the app asked for is on screen: a permission
/// alert, Google's or Apple's sign-in sheet, the App Store purchase sheet.
/// Each makes the scene go `.inactive`, which would otherwise show the
/// privacy cover on top of it (and a cover over Google's sign-in ends it as
/// cancelled). RootView reads `SystemPrompt.shared.active` to skip the cover.
@MainActor
@Observable
final class SystemPrompt {
    static let shared = SystemPrompt()
    private(set) var active = false
    private var depth = 0
    /// How long `active` stays set after the sheet closes, while the scene
    /// returns to `.active`, so the cover doesn't flash as the sheet goes.
    private let linger: Duration

    init(linger: Duration = .milliseconds(600)) {
        self.linger = linger
    }

    /// A system sheet is about to open. Pair every call with `end()`.
    func begin() {
        depth += 1
        active = true
    }

    /// The sheet closed (any way: done, cancelled, failed).
    func end() {
        Task { @MainActor in
            try? await Task.sleep(for: linger)
            depth -= 1
            if depth == 0 { active = false }
        }
    }

    /// Runs `work` (which shows a system sheet) with `active` set, and ends
    /// it on every way out, including a throw.
    func showing<T>(_ work: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await work()
    }
}

/// Local notifications the day before a predicted payment. Nothing leaves
/// the phone. Rebuilt each time the app opens, so they follow the latest
/// predictions and Raj's cancellations.
@MainActor
enum Reminders {
    static let enabledKey = "paymentReminders"
    private static let prefix = "recurring-"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Whether reminders get scheduled at all. Only the on/off setting
    /// decides: nothing is gated behind a purchase.
    nonisolated static func shouldSchedule(enabled: Bool) -> Bool { enabled }

    /// True while Apple's notification alert is up (see `SystemPrompt`).
    static var isAskingPermission: Bool { SystemPrompt.shared.active }

    /// Asks once; returns whether reminders are allowed. Apple's alert lives
    /// here and nowhere else: the aha card on Home calls it (through
    /// `turnOnCheckIn`, the one ask after setup) and so do the switches in
    /// Settings › Bills & reminders. The tap-through setup never does.
    static func requestPermission() async -> Bool {
        await SystemPrompt.shared.showing {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Whether iOS lets Sortd send notifications right now. Never asks.
    static func notificationsAllowed() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return allows(status)
    }

    nonisolated static func allows(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    /// What the Budget Pace Alert switch shows. The stored choice is kept as it
    /// is; while iOS blocks notifications the switch reads off, because the
    /// alert can never arrive (it only sends when notifications are allowed).
    nonisolated static func paceAlertShownOn(stored: Bool, notificationsAllowed: Bool) -> Bool {
        stored && notificationsAllowed
    }

    /// The aha card's "Yes": asks iOS, then schedules the check-in that was
    /// saved during setup. Not allowed: any old check-in is cleared and
    /// nothing is scheduled. Returns whether it was allowed.
    static func turnOnCheckIn(_ choice: SetupProfile.CheckIn) async -> Bool {
        let allowed = await requestPermission()
        await CheckInReminder.schedule(allowed ? choice : .needed)
        return allowed
    }

    /// The rebuild running now. App open and the Settings toggle can both
    /// call `reschedule` at once; without this, an app-open rebuild still
    /// adding reminders could finish after "off" had cleared them.
    private static var rebuilding: Task<Void, Never>?

    /// One at a time: a newer call stops the one in progress, waits for it,
    /// then clears and rebuilds from scratch.
    static func reschedule(_ recurring: [Recurring], now: Date = .now) async {
        let previous = rebuilding
        previous?.cancel()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }   // an even newer call will do it
            await rebuild(recurring, now: now)
        }
        rebuilding = task
        await task.value
        if rebuilding == task { rebuilding = nil }
    }

    private static func rebuild(_ recurring: [Recurring], now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard shouldSchedule(enabled: enabled) else { return }

        let cal = Calendar.current
        let horizon = cal.date(byAdding: .day, value: 45, to: now)!
        // iOS keeps at most 64 pending; stay well under.
        for r in recurring.filter({ $0.status == .active && $0.nextDate <= horizon }).prefix(40) {
            guard let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: r.nextDate)),
                  let fireAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
                  fireAt > now else { continue }
            // Superseded: the newer call clears whatever this one added.
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = "\(r.merchant) tomorrow"
            content.body = "\(Money.format(r.amount, r.currency)) on \(r.card.shortLabel). \(r.cadence.name)."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + r.key, content: content, trigger: trigger))
        }
    }

    // MARK: Budget pace

    private static let paceID = "budget-pace"
    /// Settings › Bills & Reminders › Budget pace alert. Its own switch,
    /// not the bills one. On by default; it only ever fires when
    /// notifications are already allowed (`checkBudgetPace` never asks).
    nonisolated static let paceAlertKey = "budgetPaceAlert"

    nonisolated static func paceAlertOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: paceAlertKey) as? Bool ?? true
    }

    /// "On track to pass your budget by the 22nd", at most once a calendar
    /// month, and only when notifications are already allowed: this never
    /// asks. Nothing when the pace is fine. The title is the whole message:
    /// no amount goes on the lock screen.
    static func checkBudgetPace(_ transactions: [Transaction], budget: Double, now: Date = .now,
                                defaults: UserDefaults = .standard, calendar: Calendar = .current) async {
        guard paceAlertOn(defaults), Pace.shouldNudge(now: now, defaults: defaults, calendar: calendar),
              let month = calendar.dateInterval(of: .month, for: now) else { return }
        let spent = transactions.filter { month.contains($0.date) }.audTotal.double
        guard let day = Pace.projectedOverDay(spent: spent, budget: budget, now: now, calendar: calendar) else { return }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = Pace.line(day: day)
        content.sound = .default
        Pace.markNudged(now: now, defaults: defaults, calendar: calendar)
        try? await center.add(UNNotificationRequest(identifier: paceID, content: content, trigger: nil))
    }

    // MARK: Category limits

    private static let limitPrefix = "category-limit-"

    /// A notification when a category first passes 80% and 100% of its
    /// monthly limit. Only when reminders are on; each one fires once a month.
    static func checkCategoryLimits(_ transactions: [Transaction], now: Date = .now,
                                    defaults: UserDefaults = .standard) async {
        guard shouldSchedule(enabled: enabled) else { return }
        let progress = CategoryBudgets.progress(for: transactions, limits: CategoryBudgets.all(defaults), now: now)
        let due = CategoryBudgets.dueAlerts(progress, month: CategoryBudgets.monthKey(now),
                                            sent: CategoryBudgets.sentAlerts(defaults))
        CategoryBudgets.saveSentAlerts(due.sent, defaults)

        let center = UNUserNotificationCenter.current()
        for alert in due.alerts {
            let name = alert.category.name
            let p = alert.progress
            let limit = Money.format(Decimal(p.limit), Money.home, cents: false)
            let content = UNMutableNotificationContent()
            switch alert.threshold {
            case .near:
                content.title = "\(name) is near its limit"
                content.body = "\(Money.format(Decimal(p.spent), Money.home, cents: false)) of \(limit) spent. \(Money.format(Decimal(p.left), Money.home, cents: false)) left this month."
            case .over:
                content.title = "\(name) is over its limit"
                content.body = "\(Money.format(Decimal(-p.left), Money.home, cents: false)) over your \(limit) limit this month."
            }
            content.sound = .default
            let id = limitPrefix + CategoryBudgets.alertKey(month: CategoryBudgets.monthKey(now),
                                                             category: alert.category, threshold: alert.threshold)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    // MARK: Apple Pay tap queue (spec 2026-09-26, failsafe #9)

    private static let tapQueuedID = "tap-queued"

    /// "A tap couldn't be saved. Open Sortd to finish it." One quiet
    /// notification for the whole queue, not one per item: a fixed
    /// identifier means a second queued tap just refreshes the same pending
    /// alert instead of piling up. Respects the existing notification
    /// permission and never asks — only the aha card and Settings do that.
    static func notifyTapQueued() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let content = UNMutableNotificationContent()
        content.title = "A tap couldn't be saved"
        content.body = "Open Sortd to finish it."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: tapQueuedID, content: content, trigger: nil))
    }

    /// Clears the "a tap couldn't be saved" alert once the queue is empty
    /// again — a successful replay at launch or in the foreground.
    static func clearTapQueuedNotice() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [tapQueuedID])
        center.removeDeliveredNotifications(withIdentifiers: [tapQueuedID])
    }
}
