import AppIntents
import SwiftData

/// Called by the Shortcuts "Transaction" automation every time Raj taps a
/// card in Wallet. Runs in the background; the app does not open.
struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase"
    static let description = IntentDescription(
        "Adds a purchase to Sortd. Use it in a Wallet automation so every Apple Pay tap is logged.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Merchant", description: "Shop name. In the automation, pick the Merchant variable.")
    var merchant: String?

    @Parameter(title: "Amount", description: "In the automation, pick the Amount variable. Text like “A$4.50” is fine.")
    var amount: String?

    @Parameter(title: "Card", description: "In the automation, pick the Wallet transaction, then Card or Pass.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        // All three on one line, so none is hidden under "Show More".
        Summary("Log \(\.$amount) at \(\.$merchant) on \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // #8 (spec 2026-09-26): if the store itself can't open, never crash
        // the process the way touching `SpendStore.container` directly
        // could — queue the raw tap instead.
        guard case .success(let container) = SpendStore.containerForIntent() else {
            let message = await TapQueue.saveForLater(merchant: merchant, amount: amount, card: card)
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
        let result = try await Self.handle(merchant: merchant, amount: amount, card: card,
                                           in: container.mainContext, book: .shared)
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: container.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }

    /// What happened to one tap. `transaction` is nil for an empty test run,
    /// or when the save itself failed (`saveFailed`) and the raw fields
    /// were queued instead — never for an ordinary logged purchase.
    struct Outcome {
        let message: String
        let transaction: Transaction?
        let merged: Bool
        var saveFailed: Bool = false
        /// A refund was noted (whole, partial or on its own row). Not a
        /// purchase, so no "Logged" notice (`LoggedNotice`).
        var refund: Bool = false
    }

    /// The merchant name the removed "Send a Test Tap" button wrote
    /// (`Spend/Views/Components/TapTestButton.swift`, deleted 25 Sep 2026).
    /// Kept as a constant, not deleted rows: old installs may still have
    /// test purchases under this name, and they must stay excluded from
    /// activation, suggestions and the Apple Pay status.
    nonisolated static let legacyTestMerchant = "Sortd Test"

    static let lastTapKey = "lastTapReceived"

    /// When Shortcuts last reached Sortd at all — including a ▶ test run that
    /// carried no purchase. Setup uses it to tell "not set up yet" apart from
    /// "set up, waiting for a real tap", which look the same from the
    /// transaction list alone.
    static let lastTapAtKey = "lastTapReceivedAt"

    /// True once Shortcuts has reached the app, whether or not it logged.
    static var shortcutHasReachedApp: Bool {
        UserDefaults.standard.object(forKey: lastTapAtKey) != nil
    }

    /// When Shortcuts last reached the app, for the Apple Pay status line.
    static var lastTapReceivedAt: Date? {
        UserDefaults.standard.object(forKey: lastTapAtKey) as? Date
    }

    /// A tap counts as the first auto-logged purchase only when it was
    /// added (not merged) and is not a legacy "Send a Test Tap" purchase.
    nonisolated static func countsAsActivation(added: Bool, merchant: String) -> Bool {
        added && merchant != legacyTestMerchant
    }

    /// Marks that Shortcuts reached Sortd, with the raw fields for Settings.
    static func recordReach(_ record: String, at now: Date) {
        UserDefaults.standard.set(record, forKey: lastTapKey)
        UserDefaults.standard.set(now, forKey: lastTapAtKey)
        UserDefaults.standard.synchronize()
    }

    /// The whole tap-handling logic, callable from tests.
    ///
    /// `trigger`: `.notification` when the fields were read from Wallet's
    /// notification (`LogWalletTapIntent`), which changes how it is matched
    /// to a tap of the same purchase (see `mergeNotification`). `record`
    /// and `seen` replace the default raw text kept for Settings and for a
    /// "needs a check" note.
    @MainActor
    static func handle(merchant: String?, amount: String?, card: String?,
                       in context: ModelContext, book: CardBook, now: Date = .now,
                       debugForceSaveFailure: Bool = false,
                       trigger: TapTrigger = .tap, record: String? = nil,
                       seen seenOverride: String? = nil) async throws -> Outcome {
        // Shortcuts sometimes hands intents an empty merchant or amount
        // (developer.apple.com/forums/thread/797233), or — a blank
        // Notification-trigger run, failsafe #13 — a magic variable's own
        // placeholder name ("Merchant", "(null)") where a real value should
        // be. Neither counts as real text: `TapField.normalize` treats both
        // as blank, so a placeholder can never masquerade as a shop.
        let amountText = TapField.normalize(amount)
        let parsed = amountText.isEmpty ? nil : AmountParser.parse(amountText)
        let name = TapField.normalize(merchant)
        let cardName = TapField.normalize(card)
        // Keep exactly what arrived, for checking the setup (Settings shows it).
        let seen = seenOverride ?? "amount “\(amount ?? "")” · merchant “\(merchant ?? "")” · card “\(card ?? "")”"
        recordReach(record ?? "\(now.formatted(date: .abbreviated, time: .standard)): \(seen)", at: now)
        // Nothing at all came in — not even a card: a bare ▶ run in
        // Shortcuts, not a Wallet tap. Nothing is saved. A card name alone
        // (no amount, no shop) is different: that's a real automation run
        // that only supplied a card, and known bug U6 used to save that
        // card name as if it were the shop. It's kept below, tagged "needs
        // a check", instead of either extreme.
        if name.isEmpty, parsed == nil, cardName.isEmpty {
            return Outcome(message: "Sortd is connected. Pay in a shop to log a purchase.",
                           transaction: nil, merged: false)
        }
        let missingAmount = parsed == nil || parsed!.amount == 0
        let missingShop = name.isEmpty
        let refund = AmountParser.isNegative(amount ?? "")
        // A notification names the card in its own words. Match it to a card
        // the person has, but only make a new card once this is sure to be
        // its own row: a purchase the tap already logged must not leave a
        // stray second card behind.
        var cardID = trigger == .notification
            ? (cardName.isEmpty ? .other : book.match(card))
            : book.matchOrCreate(cardName.isEmpty ? nil : card)
        // No currency in the text: a tap takes where the phone is; a
        // notification (often an online payment) takes the card's, then home.
        func fallbackCurrency(_ card: Card) -> String {
            trigger == .notification ? (book.info(card)?.currency ?? Money.home) : LocalCurrency.current()
        }
        let noun = trigger == .tap ? "Tap" : "Payment"
        let sender = trigger == .tap ? "Apple Pay sent" : "Wallet's notification had"

        // #8 (spec 2026-09-26): never let a throw from here on — a fetch or
        // a save failing (disk full, corrupt file, failed migration) —
        // propagate out of the intent. Queue the raw fields instead and
        // tell Shortcuts (and the person) it will be finished later.
        do {
            // Test-only seam (`debugForceSaveFailure`, default false, never
            // set outside `SpendTests`): behaves exactly as if
            // `context.save()` below had thrown, without needing a
            // genuinely broken disk to prove it — a plain parameter, not
            // shared mutable state, so parallel tests can't race on it
            // (spec 2026-09-26, failsafe #8; see `ThrowSafetyTests`).
            if debugForceSaveFailure { throw CocoaError(.fileWriteUnknown) }
            // Failsafe #14 (spec 2026-09-26): both automation triggers can
            // fire for one in-store tap — Transaction with real data,
            // Notification blank or a second copy of the same data. Ahead
            // of the general Deduper below (which needs `amount > 0` and
            // uses a much wider window built for a different job, S6's
            // same-source repeat): fold a same-card companion arriving
            // close in time into the one already logged, instead of
            // letting it become its own row. When nothing matches, the
            // same-card taps this already looked at and rejected are
            // excluded from the general Deduper too — otherwise its own
            // much wider (10-minute) same-source window could still merge
            // two real, distinct purchases minutes apart ("two coffees")
            // that this narrower, purpose-built check correctly kept apart.
            var excludeFromLog: Set<UUID> = []
            if !refund {
                let companion: CompanionResult
                switch trigger {
                case .notification:
                    companion = try Self.mergeNotification(name: name, parsed: parsed, knownCard: cardID,
                                                           cardText: cardName.isEmpty ? nil : card, book: book,
                                                           now: now, in: context)
                case .tap:
                    // A notification row for this purchase landed first
                    // (2 Oct 2026): the tap joins it, and its shop and card win.
                    if let absorbed = try Self.absorbNotificationRow(name: name, parsed: parsed, missingAmount: missingAmount,
                                                                     cardID: cardID, now: now, in: context) {
                        return absorbed
                    }
                    companion = try Self.mergeTapCompanion(name: name, missingAmount: missingAmount, missingShop: missingShop,
                                                           parsed: parsed, cardID: cardID, seen: seen, now: now, in: context)
                }
                switch companion {
                case .merged(let outcome): return outcome
                case .notMerged(let excluding): excludeFromLog = excluding
                }
            }
            // A refund tap: mark the purchase it belongs to as refunded, so the
            // total goes down. Refunds can take weeks, so look back 60 days.
            if refund, let p = parsed, p.amount > 0 {
                let currency = p.currency ?? fallbackCurrency(cardID)
                if Refunds.markRefunded(amount: p.amount, currency: currency, card: cardID, merchant: name,
                                          platform: nil, before: now, lookbackDays: 60, in: context) {
                    try context.save()
                    return Outcome(message: "Refund of \(Money.format(p.amount, currency)) from \(name.isEmpty ? "the shop" : name) noted — the purchase no longer counts",
                                   transaction: nil, merged: true, refund: true)
                }
                // No whole purchase matches: maybe this refund is only part of a
                // bigger one (one returned item from a A$59.90 basket).
                if let reduced = Refunds.markPartiallyRefunded(amount: p.amount, currency: currency, card: cardID,
                                                                 merchant: name, platform: nil, before: now,
                                                                 lookbackDays: 60, in: context) {
                    try context.save()
                    await FXService.backfill(in: context)
                    let shop = reduced.merchant.isEmpty ? (name.isEmpty ? "the shop" : name) : reduced.merchant
                    return Outcome(message: "\(Money.format(p.amount, currency)) refund on \(shop) noted",
                                   transaction: reduced, merged: true, refund: true)
                }
            }
            // "needs a check" (spec item 2/10): a blank amount, a blank shop,
            // or a card with neither — each tagged distinctly, but always
            // kept as a row, never dropped.
            let note: String
            if missingAmount, missingShop, !cardName.isEmpty {
                note = "\(Transaction.needsCheckTag)Apple Pay sent only a card (\(seen)). Tap to fix."
            } else if missingAmount {
                note = "\(Transaction.needsCheckTag)\(sender) no amount (\(seen)). Tap to fix."
            } else if missingShop {
                note = "\(Transaction.needsCheckTag)\(sender) no shop name (\(seen)). Tap to fix."
            } else {
                note = refund ? "Refund to your card" : ""
            }
            // Its own row now, so a card the notification named is kept.
            if trigger == .notification, cardID == .other, !cardName.isEmpty { cardID = book.matchOrCreate(card) }
            let purchase = IncomingPurchase(
                date: now,
                merchant: name.isEmpty ? "Unknown merchant" : name,
                amount: parsed?.amount ?? 0,
                currency: parsed?.currency ?? fallbackCurrency(cardID),
                card: cardID,
                source: .tap,
                note: note,
                tapOrigin: trigger
            )

            let outcome = try TransactionLogger.log(purchase, in: context, excluding: excludeFromLog)
            let t = outcome.transaction
            // A standalone refund tap (no earlier purchase to match) becomes its
            // own row here. It proves nothing about the person's own spending,
            // so this returns before the activation event below ever sees it.
            if refund, !t.refunded {
                t.refunded = true
                try context.save()
                return Outcome(message: "Refund of \(Money.format(t.amount, t.currencyCode)) from \(t.merchant) noted", transaction: t, merged: false, refund: true)
            }
            // The first purchase the app logged on its own (once per install).
            // A "Send a Test Tap" purchase is not one.
            if case .added = outcome, Self.countsAsActivation(added: true, merchant: name) {
                Analytics.shared.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
            }
            await FXService.backfill(in: context)

            if missingAmount, missingShop, !cardName.isEmpty {
                return Outcome(message: "Tap noted — only got a card, no shop or amount. Add it in Sortd.", transaction: t, merged: false)
            }
            if missingAmount {
                return Outcome(message: "\(noun) noted, amount missing. Add it in Sortd.", transaction: t, merged: false)
            }
            if missingShop {
                return Outcome(message: "\(noun) noted, shop missing. Add it in Sortd.", transaction: t, merged: false)
            }
            let money = Money.format(t.amount, t.currencyCode)
            switch outcome {
            case .added:
                return Outcome(message: "Logged \(money) at \(t.merchant) · \(t.category.name)", transaction: t, merged: false)
            case .merged:
                return Outcome(message: "\(money) at \(t.merchant) was already logged", transaction: t, merged: true)
            }
        } catch {
            let message = await TapQueue.saveForLater(merchant: merchant, amount: amount, card: card, date: now, trigger: trigger)
            return Outcome(message: message, transaction: nil, merged: false, saveFailed: true)
        }
    }

    /// Failsafe #14: matches and folds a same-card companion tap into one
    /// already logged. `.merged` when a match was found, already filled in
    /// and saved; `.notMerged` when nothing here applies — its `excluding`
    /// set is every same-card tap this already looked at and rejected, so
    /// the general Deduper that runs next (a much wider window, meant for a
    /// different job — S6's same-source repeat) can't re-open the question
    /// with a looser rule and merge two purchases this already kept apart.
    ///
    /// Matching is symmetric: either side can be the one missing a field
    /// (a blank companion can land before *or* after the real tap), so
    /// "blank" and "matches" are checked both ways —
    /// (a) both sides are full: only an exact match, and only within a
    ///     tight 60s window — two real purchases at the same shop for the
    ///     same amount minutes apart ("two coffees") must still become two
    ///     rows, so the same trigger firing twice needs a much closer
    ///     coincidence to tell apart from that.
    /// (b)/(c) at least one side is missing its amount and/or its shop: a
    ///     3-minute window, and every field present on either side must
    ///     agree with the other (a blank field never disagrees with
    ///     anything) — covers a blank companion arriving before or after
    ///     the real tap, and a companion that only got one field right.
    @MainActor
    static func mergeTapCompanion(name: String, missingAmount: Bool, missingShop: Bool,
                                  parsed: AmountParser.Result?, cardID: Card, seen: String,
                                  now: Date, in context: ModelContext) throws -> CompanionResult {
        let companionWindow: TimeInterval = 3 * 60
        let identicalWindow: TimeInterval = 60
        let widest = max(companionWindow, identicalWindow)
        let from = now.addingTimeInterval(-widest)
        let to = now.addingTimeInterval(widest)
        let nearby = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date <= to }))
            .filter { $0.card == cardID && $0.seenIn.contains(.tap) }
            .sorted { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }

        func matches(_ t: Transaction) -> Bool {
            let dt = abs(t.date.timeIntervalSince(now))
            let existingMissingAmount = t.amount == 0
            let existingMissingShop = t.rawMerchant.isEmpty || t.rawMerchant == "Unknown merchant"
            // A blank field on either side never disagrees; two present
            // fields must actually agree.
            let amountsAgree = missingAmount || existingMissingAmount || parsed?.amount == t.amount
            let merchantsAgree = missingShop || existingMissingShop
                || MerchantName.clean(t.rawMerchant) == MerchantName.clean(name)
            guard amountsAgree, merchantsAgree else { return false }
            let bothFull = !missingAmount && !missingShop && !existingMissingAmount && !existingMissingShop
            return dt <= (bothFull ? identicalWindow : companionWindow)
        }

        guard let t = nearby.first(where: matches) else {
            return .notMerged(excluding: Set(nearby.map(\.id)))
        }

        // Fill whatever the kept row was missing from the newcomer — a
        // blank first tap followed by a full one ends as one full row.
        if t.amount == 0, let newAmount = parsed?.amount, newAmount > 0 {
            t.amount = newAmount
            t.currencyCode = parsed?.currency ?? t.currencyCode
            t.audAmount = t.currencyCode == Money.home ? t.amount : nil
        }
        if (t.rawMerchant.isEmpty || t.rawMerchant == "Unknown merchant"), !name.isEmpty {
            t.rawMerchant = name
            t.merchant = MerchantName.clean(name)
            if t.category == .other {
                let learned = try TransactionLogger.learnedRules(in: context)
                t.category = Categorizer.category(for: name, learned: learned)
            }
        }
        t.markSeen(in: .tap)
        t.markOrigin(.tap)

        let stillMissingAmount = t.amount == 0
        let stillMissingShop = t.rawMerchant.isEmpty || t.rawMerchant == "Unknown merchant"
        let message: String
        if !stillMissingAmount, !stillMissingShop {
            // Fully resolved: the needs-a-check tag is removed, not left
            // pointing at a problem that no longer exists.
            t.note = ""
            message = "Logged \(Money.format(t.amount, t.currencyCode)) at \(t.merchant) · \(t.category.name)"
        } else if stillMissingAmount, stillMissingShop {
            t.note = "\(Transaction.needsCheckTag)Apple Pay sent only a card (\(seen)). Tap to fix."
            message = "Tap noted — only got a card, no shop or amount. Add it in Sortd."
        } else if stillMissingAmount {
            t.note = "\(Transaction.needsCheckTag)Apple Pay sent no amount (\(seen)). Tap to fix."
            message = "Tap noted, amount missing. Add it in Sortd."
        } else {
            t.note = "\(Transaction.needsCheckTag)Apple Pay sent no shop name (\(seen)). Tap to fix."
            message = "Tap noted, shop missing. Add it in Sortd."
        }
        try context.save()
        return .merged(Outcome(message: message, transaction: t, merged: true))
    }

    /// `mergeTapCompanion`'s result: either it already merged and saved, or
    /// it didn't — carrying the same-card taps it looked at, so the caller
    /// can keep the general Deduper from re-merging them under a looser rule.
    enum CompanionResult {
        case merged(Outcome)
        case notMerged(excluding: Set<UUID>)
    }

    // MARK: - One purchase, two triggers (2 Oct 2026)

    /// How far apart a tap and Wallet's notification for one purchase can
    /// land and still be matched on amount and card alone.
    static let triggerPairWindow: TimeInterval = 10 * 60

    private static func lacksShop(_ t: Transaction) -> Bool {
        t.rawMerchant.isEmpty || t.rawMerchant == "Unknown merchant"
    }

    /// Two names for one shop: either is blank, or they are the same shop
    /// however spelled ("SQ *SEVEN SEEDS" and "Seven Seeds").
    private static func shopsAgree(_ t: Transaction, _ name: String) -> Bool {
        name.isEmpty || lacksShop(t)
            || Deduper.similarity(t.rawMerchant, name) >= 0.8 || Deduper.similarity(t.merchant, name) >= 0.8
    }

    /// An unknown card on either side never disagrees; two known cards must match.
    private static func cardsAgree(_ a: Card, _ b: Card) -> Bool { a == .other || b == .other || a == b }

    private static func setShop(_ t: Transaction, to name: String, recategorise: Bool, in context: ModelContext) throws {
        t.rawMerchant = name
        t.merchant = MerchantName.clean(name)
        let category = Categorizer.category(for: name, learned: try TransactionLogger.learnedRules(in: context))
        if recategorise ? category != .other : t.category == .other { t.category = category }
    }

    /// The needs-a-check tag goes once the row has both an amount and a shop.
    private static func settleNeedsCheck(_ t: Transaction) {
        if t.amount > 0, !lacksShop(t), t.note.hasPrefix(Transaction.needsCheckTag) { t.note = "" }
    }

    private static func mergedOutcome(_ t: Transaction, noun: String) -> Outcome {
        if t.amount == 0 { return Outcome(message: "\(noun) noted, amount missing. Add it in Sortd.", transaction: t, merged: true) }
        if lacksShop(t) { return Outcome(message: "\(noun) noted, shop missing. Add it in Sortd.", transaction: t, merged: true) }
        return Outcome(message: "Logged \(Money.format(t.amount, t.currencyCode)) at \(t.merchant) · \(t.category.name)",
                       transaction: t, merged: true)
    }

    /// A notification run (it always has an amount). In order:
    /// 1. the tap of this purchase: the row only the tap trigger has
    ///    reported that is closest in time (the latest tap, in real use),
    ///    within 10 minutes either side, same amount, same card when both
    ///    know it — the shop may be spelled differently;
    /// 2. a tap that arrived with no amount: within 3 minutes, shops agree;
    /// 3. the same notification again: a row that has already seen one,
    ///    within 60 s, same amount, same shop (Wallet posting twice).
    /// A waiting tap comes first, so two coffees whose notifications both
    /// arrive after both taps still pair one each.
    /// The kept row gets the notification's shop, card or amount only where
    /// it had none. Otherwise `.notMerged`, carrying every tap row nearby so
    /// the general Deduper (same source, 10 minutes, names alike) cannot
    /// fold two separate online purchases at one shop into one.
    @MainActor
    static func mergeNotification(name: String, parsed: AmountParser.Result?, knownCard: Card, cardText: String?,
                                  book: CardBook, now: Date, in context: ModelContext) throws -> CompanionResult {
        guard let parsed, parsed.amount > 0 else { return .notMerged(excluding: []) }
        let from = now.addingTimeInterval(-triggerPairWindow)
        let to = now.addingTimeInterval(triggerPairWindow)
        let taps = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date <= to }))
            .filter { $0.seenIn.contains(.tap) && !$0.refunded }
        let candidates = taps.filter { cardsAgree($0.card, knownCard) }
        func gap(_ t: Transaction) -> TimeInterval { abs(t.date.timeIntervalSince(now)) }
        let tapOnly = candidates.filter { $0.seenByTapTrigger && !$0.seenByNotification }

        // Closest first; on a tie, the later row.
        func closer(_ a: Transaction, _ b: Transaction) -> Bool {
            gap(a) != gap(b) ? gap(a) < gap(b) : a.date > b.date
        }
        let tapRow = tapOnly.filter { $0.amount == parsed.amount }.min(by: closer)
        let blankTap = tapOnly.filter { $0.amount == 0 && gap($0) <= 3 * 60 && shopsAgree($0, name) }.min(by: closer)
        let repeatOf = candidates
            .filter { $0.seenByNotification && gap($0) <= 60 && $0.amount == parsed.amount && shopsAgree($0, name) }
            .min(by: closer)
        guard let t = tapRow ?? blankTap ?? repeatOf else {
            return .notMerged(excluding: Set(taps.map(\.id)))
        }

        if t.amount == 0 {
            t.amount = parsed.amount
            t.currencyCode = parsed.currency ?? t.currencyCode
            t.audAmount = t.currencyCode == Money.home ? t.amount : nil
        }
        if lacksShop(t), !name.isEmpty { try setShop(t, to: name, recategorise: false, in: context) }
        if t.card == .other, let cardText { t.card = knownCard != .other ? knownCard : book.matchOrCreate(cardText) }
        t.markOrigin(.notification)
        settleNeedsCheck(t)
        try context.save()
        return .merged(mergedOutcome(t, noun: "Payment"))
    }

    /// A tap run, ahead of `mergeTapCompanion`: a row only Wallet's
    /// notification has reported, within 10 minutes, same amount, same card
    /// when both know it, is this purchase — the tap joins it and the tap's
    /// shop and card win (the tap names the shop as the till does). A tap
    /// with no amount only joins one within 3 minutes whose shop agrees.
    @MainActor
    static func absorbNotificationRow(name: String, parsed: AmountParser.Result?, missingAmount: Bool,
                                      cardID: Card, now: Date, in context: ModelContext) throws -> Outcome? {
        let from = now.addingTimeInterval(-triggerPairWindow)
        let to = now.addingTimeInterval(triggerPairWindow)
        let onlyNotification = TapTrigger.notification.rawValue
        func gap(_ t: Transaction) -> TimeInterval { abs(t.date.timeIntervalSince(now)) }
        let match = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date <= to }))
            .filter { $0.tapOrigins == onlyNotification && !$0.refunded && cardsAgree($0.card, cardID) }
            .filter { t in
                missingAmount ? gap(t) <= 3 * 60 && shopsAgree(t, name) : t.amount == parsed?.amount
            }
            .min { gap($0) < gap($1) }
        guard let t = match else { return nil }

        if !name.isEmpty { try setShop(t, to: name, recategorise: true, in: context) }
        if cardID != .other { t.card = cardID }
        if !missingAmount, let currency = parsed?.currency, currency != t.currencyCode {
            t.currencyCode = currency
            t.audAmount = currency == Money.home ? t.amount : nil
        }
        t.markOrigin(.tap)
        settleNeedsCheck(t)
        try context.save()
        return mergedOutcome(t, noun: "Tap")
    }
}

struct SpendShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: ["Log a purchase in \(.applicationName)", "Add spending to \(.applicationName)"],
            shortTitle: "Log Purchase",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: LogWalletTapIntent(),
            phrases: ["Log a Wallet tap in \(.applicationName)"],
            shortTitle: "Log Wallet Tap",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: SpentThisPeriodIntent(),
            phrases: [
                "How much have I spent in \(.applicationName)",
                "How much have I spent \(\.$period) in \(.applicationName)",
                "What have I spent \(\.$period) in \(.applicationName)",
                "Ask \(.applicationName) how much I spent \(\.$period)",
            ],
            shortTitle: "Amount Spent",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: BudgetLeftIntent(),
            phrases: [
                "How much budget is left in \(.applicationName)",
                "What's left of my budget in \(.applicationName)",
                "Ask \(.applicationName) how much budget I have left",
            ],
            shortTitle: "Budget Left",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: UpcomingBillsIntent(),
            phrases: [
                "What bills are coming up in \(.applicationName)",
                "Show upcoming bills in \(.applicationName)",
                "Ask \(.applicationName) what bills are due",
            ],
            shortTitle: "Upcoming Bills",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: LastPurchaseIntent(),
            phrases: [
                "What was my last purchase in \(.applicationName)",
                "Show my last purchase in \(.applicationName)",
                "Ask \(.applicationName) what I bought last",
            ],
            shortTitle: "Last Purchase",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
