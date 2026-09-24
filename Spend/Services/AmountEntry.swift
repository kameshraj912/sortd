import Foundation

/// The one rule for typing an amount by hand, shared by the add sheet and
/// the purchase detail so both refuse the same keys (UI pass finding 12: the
/// detail took 30 digits and then quietly went back to the old value).
enum AmountEntry {
    /// Whole digits the purchase detail allows: 999,999,999, enough for an
    /// imported IDR or VND purchase. The add sheet saves under 1,000,000, so
    /// it passes 6.
    nonisolated static let detailWholeDigits = 9

    /// What the amount field accepts: digits and one decimal point (or
    /// comma), at most two decimals, and at most `wholeDigits` before it.
    nonisolated static func isTypeable(_ text: String, wholeDigits: Int = detailWholeDigits) -> Bool {
        guard !text.isEmpty else { return true }
        guard text.range(of: #"^\d*([.,]\d{0,2})?$"#, options: .regularExpression) != nil else { return false }
        let whole = text.prefix { $0.isNumber }.drop { $0 == "0" }
        return whole.count <= wholeDigits && text.count <= wholeDigits + 6
    }

    /// The text a field holds after a keystroke: the new text when it is
    /// typeable, or when it is shorter (deleting from an over-long value
    /// must always work); otherwise what was there. Never wipes a value.
    nonisolated static func accepted(_ new: String, replacing old: String,
                                     wholeDigits: Int = detailWholeDigits) -> String {
        if isTypeable(new, wholeDigits: wholeDigits) || new.count < old.count { return new }
        return old
    }
}
