import Foundation

/// The few lines where Sortd is allowed to have a personality.
///
/// The app is a money screen and money screens should be calm. Somebody
/// checking whether they can afford lunch does not want banter, and somebody
/// who has just gone over budget wants that even less. So the rule is:
///
/// **No jokes about the person or their money habits, and never on a screen
/// they opened because they were worried.**
///
/// Over budget, category limits, delete, privacy, errors and anything with a
/// number in it stay plain. Wit only goes where the stakes are zero — a
/// long-press nobody has to find — and it's at Sortd's expense, not the user's.
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

    /// The import read a file or screenshot but found no purchases in it.
    /// Plain, because they just tried to do something and it didn't work.
    /// Shown under the alert title "No Purchases Found".
    static var importFoundNothing: String {
        "If this is a bank statement, try your bank's CSV export."
    }

    #if DEBUG
    // MARK: The code screen
    //
    // Debug builds only, like `SecretCodeSheet`. These codes only go to close
    // friends, so the joke can be at their expense. It's the one screen in
    // the app where the reader definitely knows whoever wrote it.

    static var proUnlocked: String {
        [
            "Pro unlocked. You didn't pay for this and we're both going to have to live with that.",
            "Pro unlocked. Someone gave you a code instead of a birthday present. Sit with that.",
            "Pro unlocked. Free — the correct price for something you were never going to buy.",
            "Pro unlocked. Congratulations on knowing exactly one useful person.",
            "Pro unlocked. Every feature, none of the money. Classic you.",
            "Pro unlocked. Somewhere a developer is quietly recalculating his runway.",
        ].randomElement() ?? "Pro unlocked."
    }

    static var codeAlreadyUsed: String {
        [
            "Already unlocked. Don't be greedy.",
            "You have it. One is plenty. Give the next one to someone with less.",
            "Already on. Collecting these isn't a personality.",
            "Unlocked already. Typing it twice isn't a strategy.",
            "You've got it. Hoarding codes is a choice, and it's the wrong one.",
        ].randomElement() ?? "Already unlocked. Don't be greedy."
    }

    static var notACode: String {
        [
            "No. Keep going though, it's fascinating to watch.",
            "That's not it. Confidence, though. Real confidence.",
            "Nope. Whoever gave you that code was lying to you.",
            "Not a code. Just a word you typed with real conviction.",
        ].randomElement() ?? "That's not it."
    }
    #endif

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
    //   over budget · category over its limit · spending by category ·
    //   delete all data · privacy · any error · Face ID · anything with a
    //   total in it
}
