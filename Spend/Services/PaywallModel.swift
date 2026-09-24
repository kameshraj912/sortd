import Foundation
import StoreKit

// The pure parts of the Sortd Pro paywall: which screen shows, what each
// plan says, and the free-trial timeline. No SwiftUI and no App Store calls,
// so every case can be unit-tested. Buying, restoring and entitlements stay
// in `ProStore`.

/// Which paywall design people see. A PostHog feature flag will pick this
/// later (A/B test); until then everyone gets the multi-step flow.
enum PaywallVariant: String, CaseIterable, Sendable {
    /// Three short steps: what you get, how the trial works, pick a plan.
    case multiStep
    /// Everything on one sheet (the original `PaywallView`).
    case singlePage

    static var current: PaywallVariant {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SPEND_PAYWALL_VARIANT"],
           let forced = PaywallVariant(rawValue: raw) { return forced }
        #endif
        return .multiStep
    }
}

/// Where the paywall was opened from.
enum PaywallEntry: Equatable, Sendable {
    /// The last step of first-launch setup.
    case onboarding
    /// Settings › Sortd Pro.
    case settings
    /// A locked feature was tapped (ProGate, the receipt camera, Gmail…).
    case feature(ProStore.Feature)
}

/// What to show for an entry point.
enum PaywallPresentation: Equatable, Sendable {
    /// TestFlight beta: the existing "everything is free" note, no prices.
    case betaNote
    /// Already has Pro: the existing thank-you sheet.
    case owned
    /// The multi-step flow.
    case steps
    /// The single-page sheet.
    case singlePage
    /// One short sheet for the feature that was tapped.
    case compact(ProStore.Feature)

    static func make(entry: PaywallEntry, variant: PaywallVariant, betaFree: Bool, isPro: Bool) -> PaywallPresentation {
        // Beta first: nothing to sell, whatever the entry point.
        if betaFree { return .betaNote }
        if isPro { return .owned }
        if case .feature(let f) = entry { return .compact(f) }
        return variant == .multiStep ? .steps : .singlePage
    }
}

/// One screen of the multi-step flow.
enum PaywallStep: String, CaseIterable, Sendable {
    case features, trial, plans

    /// The trial step only shows when there is a free trial this person can
    /// still get. Without one it would explain something that won't happen.
    static func sequence(hasTrial: Bool) -> [PaywallStep] {
        hasTrial ? [.features, .trial, .plans] : [.features, .plans]
    }
}

/// One page of "What you get". Insights and budgets share a page.
enum PaywallPage: String, CaseIterable, Identifiable, Sendable {
    case gmail, camera, insights, bills
    var id: String { rawValue }

    /// The pages this build offers (Gmail is left out when it's off).
    static func available(gmail: Bool) -> [PaywallPage] {
        allCases.filter { $0 != .gmail || gmail }
    }

    /// The page for a locked feature.
    init(_ feature: ProStore.Feature) {
        switch feature {
        case .gmail: self = .gmail
        case .camera: self = .camera
        case .insights, .budgets: self = .insights
        case .recurring: self = .bills
        }
    }

    var headline: String {
        switch self {
        case .gmail: "Receipts from your inbox"
        case .camera: "Scan paper receipts"
        case .insights: "See where it goes"
        case .bills: "Know what's due"
        }
    }

    var sentence: String {
        switch self {
        case .gmail: "Deliveries, rides and app stores, read on this iPhone."
        case .camera: "Point the camera. Sortd fills in the shop and total."
        case .insights: "This month against last, with a limit per category."
        case .bills: "Repeat charges found, with a nudge the day before."
        }
    }

    var symbol: String {
        switch self {
        case .gmail: "envelope"
        case .camera: "doc.text.viewfinder"
        case .insights: "chart.bar"
        case .bills: "arrow.triangle.2.circlepath"
        }
    }
}

/// A free-trial length, from the App Store's introductory offer.
struct TrialPeriod: Equatable, Sendable {
    enum Unit: Sendable { case day, week, month, year }
    let value: Int
    let unit: Unit

    init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    init?(_ period: Product.SubscriptionPeriod) {
        switch period.unit {
        case .day: self.init(value: period.value, unit: .day)
        case .week: self.init(value: period.value, unit: .week)
        case .month: self.init(value: period.value, unit: .month)
        case .year: self.init(value: period.value, unit: .year)
        @unknown default: return nil
        }
    }

    /// "14 days", "1 week", "1 month". Weeks read as days so they match the
    /// "Day 12" and "Day 14" on the timeline (1 week stays "1 week").
    var text: String {
        switch unit {
        case .day: value == 7 ? "1 week" : (value == 1 ? "1 day" : "\(value) days")
        case .week: value == 1 ? "1 week" : "\(value * 7) days"
        case .month: value == 1 ? "1 month" : "\(value) months"
        case .year: value == 1 ? "1 year" : "\(value) years"
        }
    }

    /// When a trial started at `start` ends.
    func end(from start: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = switch unit {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.date(byAdding: component, value: value, to: start) ?? start
    }
}

/// One plan as the paywall shows it. Built from a StoreKit `Product`, or
/// from sample values in tests and DEBUG screenshots.
struct PaywallPlan: Identifiable, Sendable {
    enum Kind: Sendable { case yearly, monthly, lifetime }

    let id: String
    let kind: Kind
    /// The App Store's own price text ("$49.99", "S$68.98").
    let displayPrice: String
    let price: Decimal
    let format: Decimal.FormatStyle.Currency
    /// The free trial this person can still get, if any.
    let trial: TrialPeriod?
    let product: Product?

    init(id: String, kind: Kind, displayPrice: String, price: Decimal,
         format: Decimal.FormatStyle.Currency, trial: TrialPeriod? = nil, product: Product? = nil) {
        self.id = id
        self.kind = kind
        self.displayPrice = displayPrice
        self.price = price
        self.format = format
        self.trial = trial
        self.product = product
    }

    static func kind(for id: String) -> Kind {
        switch id {
        case ProStore.ID.yearly: .yearly
        case ProStore.ID.monthly: .monthly
        default: .lifetime
        }
    }

    var title: String {
        switch kind {
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .lifetime: "Lifetime"
        }
    }

    /// Under the price on the plan row.
    var priceUnit: String {
        switch kind {
        case .yearly: "a year"
        case .monthly: "a month"
        case .lifetime: "once"
        }
    }

    /// The yearly price spread over 12 months, in the store's currency and
    /// locale ("$4.17"). Nil for the other plans.
    var perMonth: String? {
        guard kind == .yearly else { return nil }
        return PaywallMath.perMonth(yearly: price, format: format)
    }

    /// Second line of the plan row.
    var detail: String {
        switch kind {
        case .yearly:
            let month = perMonth.map { "\($0) a month" }
            return [trial.map { "\($0.text) free" }, month].compactMap { $0 }.joined(separator: " · ")
        case .monthly: return trial.map { "\($0.text) free · Cancel any time" } ?? "Cancel any time"
        case .lifetime: return "Pay once. Yours for good."
        }
    }

    /// The buy button.
    var buttonTitle: String {
        if trial != nil { return "Start Free Trial" }
        switch kind {
        case .yearly: return "Subscribe Yearly"
        case .monthly: return "Subscribe Monthly"
        case .lifetime: return "Buy Lifetime"
        }
    }

    /// Apple's required renewal wording (Guideline 3.1.2), in plain words.
    var terms: String {
        switch kind {
        case .lifetime:
            return "One payment of \(displayPrice). No subscription."
        case .yearly, .monthly:
            let start = trial.map { "\($0.text) free, then " } ?? ""
            return "\(start)\(displayPrice) \(priceUnit). Renews automatically unless you cancel at least 24 hours before the end of the period, in Settings › Apple Account › Subscriptions."
        }
    }
}

enum PaywallMath {
    /// Yearly price / 12, rounded the way the currency is (2 places for
    /// dollars, none for yen), and formatted like the App Store's price.
    static func perMonth(yearly: Decimal, format: Decimal.FormatStyle.Currency) -> String {
        (yearly / 12).formatted(format)
    }
}

/// "How the free trial works": today, a reminder, the day it ends.
struct TrialTimeline: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        enum Kind: Sendable { case today, reminder, ends }
        let kind: Kind
        let date: Date
        let title: String
        let detail: String
        var id: Kind { kind }
    }

    static let reminderDaysBefore = 2

    let items: [Item]

    /// - Parameters:
    ///   - canRemind: false when notifications are turned off for Sortd, so
    ///     the timeline never promises a reminder that can't arrive.
    init(start: Date, trial: TrialPeriod, plan: PaywallPlan, canRemind: Bool, calendar: Calendar = .current) {
        let end = trial.end(from: start, calendar: calendar)
        var items = [Item(kind: .today, date: start, title: "Today",
                          detail: "Every Pro feature unlocks. Nothing to pay.")]
        if canRemind, let remind = TrialReminder.fireDate(trialEnd: end, now: start, calendar: calendar) {
            items.append(Item(kind: .reminder, date: remind, title: "Reminder",
                              detail: "A notification that your trial ends in \(Self.reminderDaysBefore) days."))
        }
        items.append(Item(kind: .ends, date: end, title: "Trial ends",
                          detail: "\(plan.displayPrice) \(plan.priceUnit) starts, unless you cancel before."))
        self.items = items
    }
}

/// When the "your trial ends soon" notification fires.
enum TrialReminder {
    static let id = "trial-ending"

    /// 9 am, two days before the trial ends. Nil when that's already past
    /// (a trial of two days or less) — then no reminder is promised.
    static func fireDate(trialEnd: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -TrialTimeline.reminderDaysBefore,
                                      to: calendar.startOfDay(for: trialEnd)),
              let at = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
              at > now else { return nil }
        return at
    }
}
