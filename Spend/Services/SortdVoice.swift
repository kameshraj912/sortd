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
        return switch name.lowercased() {
        case "eating out":
            "Eating out took \(percent)% of the month. Your kitchen is right there. It has always been right there."
        case "food delivery":
            "\(percent)% of your month arrived at the door. You didn't even have to stand up."
        case "groceries":
            "Groceries at \(percent)%. Annoyingly responsible of you."
        case "shopping":
            "Shopping took \(percent)%. You needed all of it, obviously."
        case "transport":
            "\(percent)% on getting places. At least you left the house."
        case "subscriptions":
            "Subscriptions took \(percent)% without asking once. Admirable, really."
        case "rent & housing", "housing":
            "Housing at \(percent)%. Nothing funny about that one."
        case "entertainment":
            "Entertainment took \(percent)%. Money well spent, probably, allegedly."
        default:
            "\(name) took \(percent)% of the month. Make of that what you will."
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
