import Foundation

/// A small, local, short-lived copy of a form that is half filled in, so a
/// swipe, a call or a kill does not throw the typing away. Lives in
/// UserDefaults on this phone only. Nothing here is sent anywhere, and
/// "Delete all data" removes it with the rest of the defaults.
nonisolated enum DraftStore {
    /// A draft older than this is dropped, not restored.
    static let lifetime: TimeInterval = 24 * 60 * 60

    private struct Envelope<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    static func save<Value: Codable>(_ value: Value, key: String,
                                     defaults: UserDefaults = .standard, now: Date = .now) {
        guard let data = try? JSONEncoder().encode(Envelope(savedAt: now, value: value)) else { return }
        defaults.set(data, forKey: key)
    }

    /// The saved value, or nil when there is none, it is older than 24 hours,
    /// or it cannot be read (an old shape). Expired or unreadable drafts are
    /// removed on the way out.
    static func load<Value: Codable>(_ type: Value.Type, key: String,
                                     defaults: UserDefaults = .standard, now: Date = .now) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: data),
              now.timeIntervalSince(envelope.savedAt) < lifetime,
              envelope.savedAt <= now.addingTimeInterval(60) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return envelope.value
    }

    static func clear(key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// What the New Purchase sheet holds. Enums are kept as raw strings, as in the
/// store, so a draft from an older build still reads.
nonisolated struct PurchaseDraft: Codable, Equatable, Sendable {
    var merchant = ""
    var amount = ""
    var currency = ""
    var cardRaw = ""
    var categoryRaw = ""
    var categoryTouched = false
    var date = Date.now
    var note = ""

    static let key = "draft.purchase"

    /// Only typing counts. A different card or date on an empty form is not
    /// worth keeping, and saving it would greet people with a draft they
    /// never wrote.
    var isEmpty: Bool {
        [merchant, amount, note].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Saves it, or removes the saved one when there is nothing typed.
    /// Returns true when something was kept.
    @discardableResult
    static func save(_ draft: PurchaseDraft, defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        guard !draft.isEmpty else {
            clear(defaults: defaults)
            return false
        }
        DraftStore.save(draft, key: key, defaults: defaults, now: now)
        return true
    }

    static func load(defaults: UserDefaults = .standard, now: Date = .now) -> PurchaseDraft? {
        guard let draft = DraftStore.load(PurchaseDraft.self, key: key, defaults: defaults, now: now),
              !draft.isEmpty else { return nil }
        return draft
    }

    static func clear(defaults: UserDefaults = .standard) {
        DraftStore.clear(key: key, defaults: defaults)
    }
}

/// What the New Card sheet holds. Only a new card gets a draft; an edit starts
/// from the saved card, which is already safe.
nonisolated struct CardDraft: Codable, Equatable, Sendable {
    var info: CardInfo
    var digits = ""
    var payDigits = ""
    var words = ""

    static let key = "draft.card"

    var isEmpty: Bool {
        [info.name, info.bank, digits, payDigits, words]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @discardableResult
    static func save(_ draft: CardDraft, defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        guard !draft.isEmpty else {
            clear(defaults: defaults)
            return false
        }
        DraftStore.save(draft, key: key, defaults: defaults, now: now)
        return true
    }

    static func load(defaults: UserDefaults = .standard, now: Date = .now) -> CardDraft? {
        guard let draft = DraftStore.load(CardDraft.self, key: key, defaults: defaults, now: now),
              !draft.isEmpty else { return nil }
        return draft
    }

    static func clear(defaults: UserDefaults = .standard) {
        DraftStore.clear(key: key, defaults: defaults)
    }
}
