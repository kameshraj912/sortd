import Foundation

/// The one rule for typing an amount by hand, shared by the add sheet and
/// the purchase detail so both refuse the same keys (UI pass finding 12: the
/// detail took 30 digits and then quietly went back to the old value).
enum AmountEntry {
    /// Amounts must be under this (1,000,000), the same line as `QuickEntry`.
    nonisolated static let limit: Decimal = QuickEntry.limit

    /// What the amount field accepts: digits and one decimal point (or
    /// comma), at most two decimals, and less than 1,000,000.
    nonisolated static func isTypeable(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard text.range(of: #"^\d*([.,]\d{0,2})?$"#, options: .regularExpression) != nil else { return false }
        let whole = text.prefix { $0.isNumber }.drop { $0 == "0" }
        return whole.count <= 6 && text.count <= 12
    }

    /// The text a field holds after a keystroke: the new text when it is
    /// typeable, otherwise what was there (or nothing, if that was bad too).
    /// A refused key never reverts to some older saved value later.
    nonisolated static func accepted(_ new: String, replacing old: String) -> String {
        if isTypeable(new) { return new }
        return isTypeable(old) ? old : ""
    }
}
