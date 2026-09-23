import Foundation

/// One thing left to set up. Shared by the plan screen at the end of setup
/// and the "Finish setup" card on Home, so the two always agree.
struct SetupTask: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case answers, cards, applePay, widget, gmail }
    let kind: Kind
    let symbol: String
    let title: String
    let detail: String
    let pro: Bool
    var done: Bool
    var id: String { kind.rawValue }
}

/// What's left, worked out from real data (cards added, a tap logged, a
/// widget on the Home Screen, Gmail connected), never from a guess.
enum SetupChecklist {
    /// "Hide" on the Home card.
    static let hiddenKey = "setup.checklistHidden"

    static func tasks(flow: SetupFlow, hasCards: Bool, tapped: Bool,
                      widgetAdded: Bool, gmailConnected: Bool) -> [SetupTask] {
        // Starts one step in: answering the questions counts (people finish
        // a list that's already begun more often than a blank one).
        var list = [SetupTask(kind: .answers, symbol: "checklist", title: "Answer a few questions",
                              detail: "Done", pro: false, done: true)]
        list.append(SetupTask(kind: .cards, symbol: "creditcard", title: "Add the cards you pay with",
                              detail: "30 seconds", pro: false, done: hasCards))
        if flow.payment == .cash {
            list.append(SetupTask(kind: .widget, symbol: "square.grid.2x2", title: "Add Sortd to your Home Screen",
                                  detail: "Log cash in one tap", pro: false, done: widgetAdded))
        } else {
            list.append(SetupTask(kind: .applePay, symbol: "wave.3.right", title: "Log Apple Pay by itself",
                                  detail: "2 minutes, once", pro: false, done: tapped))
        }
        if flow.gmailFeature, flow.wantsGmail {
            list.append(SetupTask(kind: .gmail, symbol: "envelope", title: "Catch receipts from Gmail",
                                  detail: "1 minute", pro: true, done: gmailConnected))
        }
        return list
    }

    static func doneCount(_ tasks: [SetupTask]) -> Int { tasks.filter(\.done).count }
    static func isComplete(_ tasks: [SetupTask]) -> Bool { tasks.allSatisfy(\.done) }
}
