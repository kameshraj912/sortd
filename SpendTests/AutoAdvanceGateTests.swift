import Testing
@testable import Spend

/// `PaymentPage`'s guard against the payment question's own bug (UX pass,
/// fresh-user walkthrough): a pick auto-advances ~350ms later, and without
/// this gate a fast second tap (the same option or another one) queued a
/// second advance and skipped the next question.
struct AutoAdvanceGateTests {
    @Test func firstFireArmsAndSucceeds() {
        var gate = AutoAdvanceGate()
        #expect(!gate.armed)
        let fired = gate.fire()
        #expect(fired)
        #expect(gate.armed)
    }

    @Test func secondFireInTheSameVisitDoesNothing() {
        var gate = AutoAdvanceGate()
        let first = gate.fire()
        let second = gate.fire()
        let third = gate.fire()
        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func aFreshGateIsAnUnarmedVisit() {
        // A new visit to the page (a fresh `@State`) is a fresh gate: it
        // fires again, independent of any earlier visit.
        let first = AutoAdvanceGate()
        var second = AutoAdvanceGate()
        #expect(!first.armed)
        let fired = second.fire()
        #expect(fired)
    }
}
