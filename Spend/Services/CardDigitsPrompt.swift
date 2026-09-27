import Foundation

/// A receipt or bank alert's last-4 that matched none of Raj's cards
/// (`EmailSync`, spec 2026-09-27 "Which card?"). With one active card the
/// digits are obviously its own — `CardBook.noteUnmatchedDigits` saves them
/// straight away, no prompt. With two or more, nobody can guess, so the
/// digits wait here for Home's "Which card?" card to ask. With none active,
/// there is nothing to attach them to.
enum PendingCardDigits {
    static let key = "pendingCardDigits"
    /// At most this many unanswered digit sets at once.
    static let cap = 5

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Adds `digits`, deduped. Past `cap`, the oldest goes so the newest
    /// unknown card always gets a turn.
    static func adding(_ digits: String, to queue: [String]) -> [String] {
        guard !queue.contains(digits) else { return queue }
        let next = queue + [digits]
        return next.count > cap ? Array(next.suffix(cap)) : next
    }

    static func removing(_ digits: String, from queue: [String]) -> [String] {
        queue.filter { $0 != digits }
    }

    static func note(_ digits: String, defaults: UserDefaults = .standard) {
        defaults.set(adding(digits, to: load(from: defaults)), forKey: key)
    }

    /// Removes `digits`, whether a card was picked for them or "Not one of
    /// mine" was tapped. Returns the queue left, for the caller's own state.
    @discardableResult
    static func clear(_ digits: String, defaults: UserDefaults = .standard) -> [String] {
        let next = removing(digits, from: load(from: defaults))
        defaults.set(next, forKey: key)
        return next
    }
}

/// Whether Home's "Which card?" card should show.
enum CardDigitsPrompt {
    /// `duringSetup`/`duringIntro` cover first-run setup and the app intro
    /// (`TipState.setupShowing` / `.introShowing`): the prompt never sits on
    /// top of either. With fewer than two active cards the queue is always
    /// empty in practice (`CardBook.noteUnmatchedDigits` settles one card or
    /// zero on its own), but the count is still checked here so the rule
    /// reads as the whole story, not half of it split across two places.
    static func shouldShow(queue: [String], activeCardCount: Int, duringSetup: Bool, duringIntro: Bool) -> Bool {
        !queue.isEmpty && activeCardCount >= 2 && !duringSetup && !duringIntro
    }
}
