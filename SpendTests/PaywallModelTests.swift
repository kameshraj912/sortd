import Testing
import Foundation
@testable import Spend

/// The paywall's pure logic: per-month price, trial wording and dates,
/// and which screen shows where. No StoreKit session needed.
@MainActor
struct PaywallModelTests {
    private let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))

    private func plan(_ kind: PaywallPlan.Kind, _ price: Decimal, _ display: String,
                      trial: TrialPeriod? = nil, format: Decimal.FormatStyle.Currency? = nil) -> PaywallPlan {
        let id = switch kind {
        case .yearly: ProStore.ID.yearly
        case .monthly: ProStore.ID.monthly
        case .lifetime: ProStore.ID.lifetime
        }
        return PaywallPlan(id: id, kind: kind, displayPrice: display, price: price, format: format ?? usd, trial: trial)
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: Per-month price

    @Test func perMonthFromYearlyPrice() {
        #expect(PaywallMath.perMonth(yearly: 49.99, format: usd) == "$4.17")
        #expect(PaywallMath.perMonth(yearly: 59.99, format: usd) == "$5.00")
        #expect(PaywallMath.perMonth(yearly: 24, format: usd) == "$2.00")
        #expect(plan(.yearly, 49.99, "$49.99").perMonth == "$4.17")
        #expect(plan(.monthly, 6.99, "$6.99").perMonth == nil)
        #expect(plan(.lifetime, 99.99, "$99.99").perMonth == nil)
    }

    @Test func perMonthFollowsTheStoreCurrency() {
        // Yen has no cents; Singapore dollars keep their own symbol.
        let yen = Decimal.FormatStyle.Currency(code: "JPY", locale: Locale(identifier: "ja_JP"))
        #expect(PaywallMath.perMonth(yearly: 7800, format: yen) == "¥650")
        let sgd = Decimal.FormatStyle.Currency(code: "SGD", locale: Locale(identifier: "en_SG"))
        #expect(PaywallMath.perMonth(yearly: 68.98, format: sgd) == "$5.75")
    }

    // MARK: Trial length

    @Test func trialLengthText() {
        #expect(TrialPeriod(value: 2, unit: .week).text == "14 days")
        #expect(TrialPeriod(value: 1, unit: .week).text == "1 week")
        #expect(TrialPeriod(value: 7, unit: .day).text == "1 week")
        #expect(TrialPeriod(value: 3, unit: .day).text == "3 days")
        #expect(TrialPeriod(value: 1, unit: .day).text == "1 day")
        #expect(TrialPeriod(value: 1, unit: .month).text == "1 month")
        #expect(TrialPeriod(value: 3, unit: .month).text == "3 months")
    }

    @Test func planWordingUsesTheRealTrial() {
        let yearly = plan(.yearly, 49.99, "$49.99", trial: TrialPeriod(value: 1, unit: .month))
        #expect(yearly.detail == "1 month free · $4.17 a month")
        #expect(yearly.buttonTitle == "Start Free Trial")
        #expect(yearly.terms.hasPrefix("1 month free, then $49.99 a year. Renews automatically"))

        let noTrial = plan(.yearly, 49.99, "$49.99")
        #expect(noTrial.detail == "$4.17 a month")
        #expect(noTrial.buttonTitle == "Subscribe Yearly")
        #expect(noTrial.terms.hasPrefix("$49.99 a year. Renews automatically"))

        let monthly = plan(.monthly, 6.99, "$6.99")
        #expect(monthly.buttonTitle == "Subscribe Monthly")
        #expect(monthly.terms.contains("24 hours"))

        let lifetime = plan(.lifetime, 99.99, "$99.99")
        #expect(lifetime.buttonTitle == "Buy Lifetime")
        #expect(lifetime.terms == "One payment of $99.99. No subscription.")
    }

    // MARK: Trial timeline

    @Test func timelineForTwoWeekTrial() throws {
        let start = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 17)))
        let yearly = plan(.yearly, 49.99, "$49.99", trial: TrialPeriod(value: 2, unit: .week))
        let t = TrialTimeline(start: start, trial: yearly.trial!, plan: yearly, canRemind: true, calendar: utc)
        #expect(t.items.map(\.kind) == [.today, .reminder, .ends])
        let end = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 17)))
        #expect(t.items[2].date == end)
        // 9 am, two days before the end.
        let remind = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9)))
        #expect(t.items[1].date == remind)
        #expect(t.items[2].detail == "$49.99 a year starts, unless you cancel before.")
    }

    @Test func noReminderPromisedWhenNotificationsAreOff() throws {
        let start = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 17)))
        let yearly = plan(.yearly, 49.99, "$49.99", trial: TrialPeriod(value: 2, unit: .week))
        let t = TrialTimeline(start: start, trial: yearly.trial!, plan: yearly, canRemind: false, calendar: utc)
        #expect(t.items.map(\.kind) == [.today, .ends])
    }

    @Test func noReminderForAVeryShortTrial() throws {
        let start = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 17)))
        let end = TrialPeriod(value: 2, unit: .day).end(from: start, calendar: utc)
        // Two days before the end is today at 9 am: already past.
        #expect(TrialReminder.fireDate(trialEnd: end, now: start, calendar: utc) == nil)
        let longer = TrialPeriod(value: 3, unit: .day).end(from: start, calendar: utc)
        #expect(TrialReminder.fireDate(trialEnd: longer, now: start, calendar: utc) != nil)
    }

    // MARK: Which screen shows

    @Test func betaNeverShowsAPaywall() {
        for entry in [PaywallEntry.onboarding, .settings, .feature(.camera)] {
            for variant in PaywallVariant.allCases {
                #expect(PaywallPresentation.make(entry: entry, variant: variant, betaFree: true, isPro: true) == .betaNote)
                #expect(PaywallPresentation.make(entry: entry, variant: variant, betaFree: true, isPro: false) == .betaNote)
            }
        }
    }

    @Test func presentationPerEntryAndVariant() {
        #expect(PaywallPresentation.make(entry: .settings, variant: .multiStep, betaFree: false, isPro: false) == .steps)
        #expect(PaywallPresentation.make(entry: .onboarding, variant: .multiStep, betaFree: false, isPro: false) == .steps)
        #expect(PaywallPresentation.make(entry: .settings, variant: .singlePage, betaFree: false, isPro: false) == .singlePage)
        #expect(PaywallPresentation.make(entry: .onboarding, variant: .singlePage, betaFree: false, isPro: false) == .singlePage)
        // A locked feature always gets the short sheet, whatever the variant.
        #expect(PaywallPresentation.make(entry: .feature(.budgets), variant: .multiStep, betaFree: false, isPro: false) == .compact(.budgets))
        #expect(PaywallPresentation.make(entry: .feature(.budgets), variant: .singlePage, betaFree: false, isPro: false) == .compact(.budgets))
        #expect(PaywallPresentation.make(entry: .settings, variant: .multiStep, betaFree: false, isPro: true) == .owned)
    }

    @Test func defaultVariantIsMultiStep() {
        #expect(PaywallVariant.current == .multiStep)
    }

    @Test func stepsSkipTheTrialWhenThereIsNone() {
        #expect(PaywallStep.sequence(hasTrial: true) == [.features, .trial, .plans])
        #expect(PaywallStep.sequence(hasTrial: false) == [.features, .plans])
    }

    @Test func pagesForFeatures() {
        #expect(PaywallPage(.budgets) == .insights)
        #expect(PaywallPage(.insights) == .insights)
        #expect(PaywallPage(.recurring) == .bills)
        #expect(PaywallPage.available(gmail: false) == [.camera, .insights, .bills])
        #expect(PaywallPage.available(gmail: true).count == 4)
        // Headlines stay short (five words at most).
        for p in PaywallPage.allCases { #expect(p.headline.split(separator: " ").count <= 5) }
    }
}
