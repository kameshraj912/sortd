import Foundation

/// The lines where Sortd is allowed to have a personality.
///
/// The app is a money screen and money screens should be calm. Somebody
/// checking whether they can afford lunch does not want banter, and somebody
/// who has just gone over budget wants that even less. So the rule is:
///
/// **Never joke about how much someone spent, and never joke on a screen
/// they opened because they were worried.** Over budget, category limits,
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
            "Nothing here yet. Enjoy it while it lasts.",
            "Empty. Either you've been very good or very offline.",
            "No purchases yet. Suspiciously responsible of you.",
        ], seed: today)
    }

    static var noInsights: String {
        stable([
            "Nothing to chart yet. Charts need spending, and spending needs you.",
            "No patterns yet. Give it a week and there will be patterns.",
        ], seed: today)
    }

    static var noRecurring: String {
        stable([
            "None found yet. There's always one. Usually two.",
            "Nothing repeating yet. Give it a month.",
        ], seed: today)
    }

    /// The import found a file but nothing in it. Mild, because they did
    /// just try to do something and it didn't work.
    static var importFoundNothing: String {
        "Sortd read the file and found no purchases in it. If it's a statement, the CSV export from your bank usually works best."
    }

    /// One line about the category that ran away with the month. The
    /// website already does this joke ("It was takeaway. It's always
    /// takeaway.") and it only lands when the category really is dominant,
    /// so it stays quiet below a third of the month's spending.
    ///
    /// This is about a category, never about the person — "eating out won"
    /// rather than "you ate out too much". The difference matters on a
    /// screen somebody opened because they were worried.
    static func topCategory(_ name: String, share: Double) -> String? {
        guard share >= 0.33 else { return nil }
        return switch name.lowercased() {
        case "eating out", "food delivery":
            "It was takeaway. It's always takeaway."
        case "groceries":
            "Groceries won. The boring answer is usually the right one."
        case "shopping":
            "Shopping took the month. No notes."
        case "transport":
            "Mostly getting places. Which is at least useful."
        case "subscriptions":
            "Subscriptions. Quietly, all month, without being asked."
        default:
            "\(name) took the biggest share this month."
        }
    }

    // MARK: Milestones — a one-off, never repeated

    /// Shown once, the first time someone passes 100 logged purchases.
    static let hundredPurchases = "100 purchases logged. That's 100 things you'd otherwise have forgotten about by Thursday."

    static let firstImport = "Imported. Your past is now searchable. Sorry."

    // MARK: Hidden

    /// Long press the mark under a title.
    static var brandMarkPress: String {
        stable([
            "Four colours. We agonised over them.",
            "You pressed the little stripes. We're not judging. Much.",
            "That's the logo. It doesn't do anything. Thanks for checking.",
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
