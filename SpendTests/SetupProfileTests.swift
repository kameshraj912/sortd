import Testing
import Foundation
@testable import Spend

/// Setup answers decide which steps show and what Pro leads with.
@MainActor
struct SetupProfileTests {

    @Test func goalsSurviveBeingSaved() {
        let goals: Set<SetupProfile.Goal> = [.spendLess, .bills]
        #expect(SetupProfile.goals(SetupProfile.raw(goals)) == goals)
        #expect(SetupProfile.goals("") == [])
        #expect(SetupProfile.goals("nonsense,bills") == [.bills])
    }

    @Test func proLeadsWithWhatTheyPicked() {
        let bills = SetupProfile.proOrder(goals: [.bills], payment: .applePay)
        #expect(bills.first == .recurring)
        let budget = SetupProfile.proOrder(goals: [.spendLess], payment: nil)
        #expect(budget.first == .budgets)
        // Every Pro feature is still listed, once.
        #expect(Set(bills).count == bills.count)
        #expect(Set(bills) == Set(ProStore.Feature.available))
    }

    @Test func onlineShoppersSeeReceiptsFirst() {
        let order = SetupProfile.proOrder(goals: [], payment: .online)
        let first = order.first
        #expect(first == .gmail || first == .camera)
    }

    @Test func quietModeSchedulesNothing() {
        #expect(SetupProfile.CheckIn.needed.time == nil)
        #expect(SetupProfile.CheckIn.sunday.time?.weekday == 1)
        #expect(SetupProfile.CheckIn.morning.time?.hour == 8)
    }
}
