import Foundation

/// The lines where Sortd is allowed to have a personality.
///
/// The app is a money screen and money screens should be calm. Somebody
/// checking whether they can afford lunch does not want banter, and somebody
/// who has just gone over budget wants that even less. So the rule is:
///
/// **Roast the habit, never the person, and never on a screen they opened
/// because they were worried.**
///
/// Being told your takeaway habit is a habit is funny. Being told you're
/// bad with money while staring at a number you're frightened of is not. Over budget, category limits,
/// delete, privacy, errors and anything with a number in it stay plain.
///
/// Wit goes where the stakes are zero: empty states nobody is stuck on,
/// a milestone, a long-press nobody has to find. The tone matches the
/// website — dry, quick, at Sortd's expense rather than the user's.
///
/// All of it lives here so it can be read in one go and toned down in one
/// place, rather than being scattered through the views.
nonisolated enum SortdVoice {

    /// Picks the same line for the same day, so the app doesn't feel like
    /// it's shuffling jokes every time the view redraws.
    private static func stable(_ options: [String], seed: Int) -> String {
        guard !options.isEmpty else { return "" }
        return options[abs(seed) % options.count]
    }

    private static var today: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
    }

    // MARK: Empty states — nothing has gone wrong, nobody is stuck

    static var noPurchases: String {
        stable([
            "Nothing logged. Either you're broke or you're lying to yourself.",
            "Empty. Bold move, installing a spending tracker and then not spending.",
            "No purchases. Give it a Friday.",
        ], seed: today)
    }

    static var noInsights: String {
        stable([
            "Nothing to chart. Charts need spending. You know what to do, unfortunately.",
            "No patterns yet. There will be. There always are.",
        ], seed: today)
    }

    static var noRecurring: String {
        stable([
            "None found yet. They're out there. Waiting. Charging quietly.",
            "Nothing repeating yet. Give it a month and prepare to be disappointed.",
        ], seed: today)
    }

    /// The import found a file but nothing in it. Mild, because they did
    /// just try to do something and it didn't work.
    static var importFoundNothing: String {
        "Sortd read the file and found no purchases in it. If it's a statement, the CSV export from your bank usually works best."
    }

    /// One dry line about the category that ran away with the month.
    ///
    /// Deliberately not the website's takeaway joke. That one is already
    /// on the homepage and in the ads, and a joke you've heard three times
    /// stops being a joke and starts being a tic. These are observations
    /// rather than punchlines, and they only appear when one category took
    /// two fifths of the month, so most months say nothing at all.
    ///
    /// Always about the category, never the person — "eating out won"
    /// rather than "you ate out too much". That line matters on a screen
    /// somebody opened because they were worried.
    static func topCategory(_ name: String, share: Double) -> String? {
        guard share >= 0.4 else { return nil }
        let percent = Int((share * 100).rounded())
        let lines = categoryLines(name.lowercased(), percent: percent, name: name)
        return stable(lines, seed: today &+ percent)
    }

    /// Several per category, picked by the day, so the same joke doesn't
    /// greet you every time you open Insights.
    ///
    /// The test each one has to pass: would you say it to a friend who just
    /// showed you their spending? Teasing the habit is fine. Telling someone
    /// they're irresponsible, broke, greedy or stupid is not, and none of
    /// these do. Housing and health get gentle ones on purpose — nobody
    /// chooses rent, and nobody needs a joke about a medical bill.
    private static func categoryLines(_ key: String, percent: Int, name: String) -> [String] {
        switch key {
        case "eating out":
            [
                "Eating out took \(percent)% of the month. Your kitchen is right there. It has always been right there.",
                "\(percent)% on eating out. Someone else did the washing up, at least.",
                "Eating out: \(percent)%. A strong month for restaurants.",
                "\(percent)% of the month was somebody else's cooking. Worth it, probably.",
            ]
        case "food delivery":
            [
                "\(percent)% of your month arrived at the door. You didn't even have to stand up.",
                "Food delivery took \(percent)%. The rider knows. The rider has always known.",
                "\(percent)% on delivery. Convenience has a price, and this is it.",
                "Delivery: \(percent)%. Your front door is doing a lot of work.",
            ]
        case "groceries":
            [
                "Groceries at \(percent)%. Annoyingly responsible of you.",
                "\(percent)% on groceries. The boring answer, and the right one.",
                "Groceries took \(percent)%. Nothing to see here. Genuinely.",
                "\(percent)% on actual food from an actual shop. Look at you.",
            ]
        case "shopping":
            [
                "Shopping took \(percent)%. You needed all of it, obviously.",
                "\(percent)% on shopping. Every single item was essential.",
                "Shopping: \(percent)%. The parcels are a coincidence.",
                "\(percent)% shopping. It was on sale, so really you saved money.",
            ]
        case "transport":
            [
                "\(percent)% on getting places. At least you left the house.",
                "Transport took \(percent)%. Movement isn't free, it turns out.",
                "\(percent)% on transport. You went somewhere. That's something.",
                "Transport: \(percent)%. The city is charging you rent to move around it.",
            ]
        case "subscriptions":
            [
                "Subscriptions took \(percent)% without asking once. Admirable, really.",
                "\(percent)% on subscriptions. They renewed while you slept.",
                "Subscriptions: \(percent)%. Quietly, monthly, forever.",
                "\(percent)% went to things that bill themselves. Efficient.",
            ]
        case "entertainment":
            [
                "Entertainment took \(percent)%. Money well spent, allegedly.",
                "\(percent)% on having a good time. Hard to argue with.",
                "Entertainment: \(percent)%. You were entertained, so it worked.",
                "\(percent)% on fun. The system works.",
            ]
        case "rent & housing", "housing":
            [
                "Housing at \(percent)%. Nothing funny about that one.",
                "\(percent)% on having somewhere to live. Non-negotiable.",
                "Housing took \(percent)%. That's just the number.",
            ]
        case "health":
            [
                "Health took \(percent)%. Worth every cent.",
                "\(percent)% on health. Good.",
            ]
        case "bills":
            [
                "Bills took \(percent)%. They're very consistent, bills.",
                "\(percent)% on bills. Nobody has ever enjoyed this number.",
                "Bills: \(percent)%. The least fun money you'll spend.",
            ]
        case "travel":
            [
                "Travel took \(percent)%. You'll remember this one, at least.",
                "\(percent)% on travel. Expensive, and completely worth it.",
                "Travel: \(percent)%. The photos had better be good.",
            ]
        case "education":
            [
                "Education took \(percent)%. An investment, genuinely this time.",
                "\(percent)% on learning things. Hard to complain about.",
                "Education: \(percent)%. Future you says thanks.",
            ]
        case "transfers":
            [
                "Transfers took \(percent)%. Money moving sideways.",
                "\(percent)% moved somewhere else. It still counts.",
            ]
        default:
            [
                "\(name) took \(percent)% of the month. Make of that what you will.",
                "\(percent)% went to \(name). Now you know.",
                "\(name): \(percent)%. Filed under 'worth knowing'.",
            ]
        }
    }

    // MARK: Milestones — a one-off, never repeated

    /// Shown once, the first time someone passes 100 logged purchases.
    static let hundredPurchases = "100 purchases logged. That's 100 things you'd have sworn you didn't buy."

    static let firstImport = "Imported. Your past is now searchable. Sorry about that."

    // MARK: Hidden

    /// Long press the mark under a title.
    static var brandMarkPress: String {
        stable([
            "Four colours. We agonised over them. You held them down.",
            "You long-pressed a logo. On a budgeting app. On purpose.",
            "It doesn't do anything. You checked anyway. Respect.",
        ], seed: today)
    }

    // MARK: Lines that must stay plain
    //
    // Kept here as a list on purpose, so the next person to add a joke can
    // see where not to put one.
    //
    //   over budget · category over its limit · delete all data · privacy
    //   · any error · Face ID · anything with a total in it
}
