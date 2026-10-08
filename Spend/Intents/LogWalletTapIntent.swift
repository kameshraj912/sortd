import AppIntents
import SwiftData

/// A field counts as blank when it is empty after trimming — including
/// zero-width and non-breaking whitespace Shortcuts can leave behind when a
/// magic variable resolves to nothing — or when it is exactly one of
/// Shortcuts' own placeholder strings for an unfilled variable (spec
/// 2026-09-26, failsafe #13: a blank Notification-trigger run must never be
/// read as a real purchase with a garbage merchant name, and must never be
/// read as a harmless ▶ preview either).
nonisolated enum TapField {
    /// Case-insensitive: Shortcuts' own capitalisation is not guaranteed to
    /// survive every code path that touches this text.
    private static let placeholders: Set<String> = [
        "amount", "merchant", "card or pass", "name", "title", "subtitle", "body",
        "(null)", "nil", "\"\"",
    ]

    /// Whitespace plus the invisible characters a copy-pasted or
    /// automation-generated string can carry that `.whitespacesAndNewlines`
    /// does not already strip.
    private static let invisible = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"))

    /// The value with invisible characters trimmed, or "" when it is blank
    /// by either definition above.
    static func normalize(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: invisible)
        return placeholders.contains(trimmed.lowercased()) ? "" : trimmed
    }

    static func isBlank(_ value: String?) -> Bool { normalize(value).isEmpty }

    /// How a field arrived, never what it said: "empty", "placeholder" (a
    /// magic variable's own name) or its length. This is all the run log in
    /// Settings keeps, so a shop name or an amount cannot outlive the
    /// purchase it came from.
    static func shape(_ value: String?) -> String {
        let n = normalize(value).count
        if n > 0 { return "\(n) characters" }
        let raw = value?.trimmingCharacters(in: invisible) ?? ""
        return raw.isEmpty ? "empty" : "placeholder"
    }
}

/// Wallet's notification as the iOS 27 Notification trigger hands it over.
/// Any one part non-blank (`TapField` rules) makes it a notification run;
/// all three blank means the tap trigger ran (or a ▶ test) and the
/// notification is ignored.
nonisolated struct WalletNotification: Equatable, Sendable {
    var title: String?
    var subtitle: String?
    var body: String?
    /// Notification › App: which app sent it (9 Oct 2026). Blank from a
    /// shortcut made before then. Whether iOS hands over the app's name or
    /// its bundle id is not known yet, so `source` takes either.
    var app: String? = nil

    /// Which app sent it, as far as `app` says.
    enum Source: Equatable { case wallet, bank, unknown }

    /// Blank, or Shortcuts' own "App" placeholder: unknown (an old
    /// shortcut). Wallet only by its exact name or bundle id, never by
    /// "wallet" inside another name ("TNG eWallet" is a money app; review,
    /// 8 Oct 2026). Any other app: one the person added to the trigger, so
    /// their bank's.
    var source: Source {
        let name = TapField.normalize(app).trimmingCharacters(in: Self.directionMarks).lowercased()
        if name.isEmpty || name == "app" { return .unknown }
        return Self.walletNames.contains(name) ? .wallet : .bank
    }

    private static let directionMarks = CharacterSet(charactersIn: "\u{200E}\u{200F}")

    /// Wallet's names, lower case: English and its bundle id, then its
    /// display name in every language, read from `CFBundleDisplayName` in
    /// the iOS 26.5 simulator runtime's
    /// `Applications/Passbook.app/*.lproj/InfoPlist.strings` (8 Oct 2026).
    static let walletNames: Set<String> = Set([
        "wallet", "apple wallet", "apple pay", "com.apple.passbook", "passbook",
        "المحفظة", "Портфейл", "ওয়ালেট", "Cartera", "Peněženka", "Πορτοφόλι", "Lompakko", "Cartes",
        "Portefeuille", "વૉલેટ", "ארנק", "वॉलेट", "Novčanik", "Tárca", "Dompet", "ウォレット", "ವಾಲೆಟ್",
        "지갑", "Piniginė", "വാലറ്റ്", "Lommebok", "ୱଲେଟ୍", "ਵੌਲਿਟ", "Portfel", "Carteira", "Portofel",
        "Peňaženka", "Denarnica", "Plånbok", "வாலெட்", "వాలెట్", "กระเป๋าสตางค์", "Cüzdan", "Гаманець",
        "والیٹ", "Ví", "钱包", "銀包", "錢包",
    ].map { $0.lowercased() })

    var isPresent: Bool { !TapField.isBlank(title) || !TapField.isBlank(subtitle) || !TapField.isBlank(body) }

    /// The non-blank parts, one per line, in Title, Subtitle, Body order.
    var joined: String {
        [title, subtitle, body].map(TapField.normalize).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Exactly what arrived, for the "needs a check" note.
    var seen: String {
        "title \u{201C}\(title ?? "")\u{201D} · subtitle \u{201C}\(subtitle ?? "")\u{201D} · body \u{201C}\(body ?? "")\u{201D}"
    }

    /// How it arrived, without the words (see `TapField.shape`): what the
    /// run log keeps.
    var shape: String {
        "title \(TapField.shape(title)) · subtitle \(TapField.shape(subtitle)) · body \(TapField.shape(body))"
            + " · app \(TapField.shape(app))"
    }

    /// Read by the bank's reader (`BankNotice`): sent by a bank's app, or
    /// text that reads as a bank's sentence, from Wallet or with no app (an
    /// old shortcut; review, 8 Oct 2026: the same reading for both).
    /// Its run is a bank run (`TapTrigger.bank`, run log kind "bank").
    var isBankNotice: Bool {
        switch source {
        case .bank: true
        case .wallet, .unknown: BankNotice.isSentence(joined)
        }
    }

    /// What one notification says: Wallet's short lines, or a bank app's
    /// sentence (`BankNotice`, 8 Oct 2026).
    enum Reading: Equatable {
        /// A payment with an amount. `amount` starts with "-" for a refund,
        /// so it takes the existing refund path.
        case payment(amount: String, merchant: String?, card: String?)
        /// The payment did not go through ("declined", "failed"…).
        case notCompleted
        /// No amount at all: a boarding pass, an order update, a card added.
        case noAmount
        /// Money came in ("You received $25.00 from …", a deposit): not
        /// spending. A refund is not this: it takes the refund path.
        case moneyIn
        /// A bank app's notification that is not a purchase: a code, a
        /// balance, a bill reminder, an offer, or an amount with no spend
        /// word. Nothing is saved, not even a "needs a check" row.
        case notAPurchase
    }

    /// Wording that means no money moved. Checked before anything else, so
    /// "Payment declined · A$23.40" is never logged. `BankNotice` uses it too.
    static let notCompletedPattern =
        #"\b(?:declined|not completed|failed|unsuccessful|couldn['’]t be|could not be|insufficient)\b"#
    static let refundPattern = #"\brefund(?:ed|s)?\b"#
    /// Wording that means money came to the person, not from them. Not a
    /// bare "deposit": paying a booking deposit is spending.
    private static let moneyInPattern =
        #"\b(?:you(?:['’]ve| have)? received|received from|sent you|deposited|deposit (?:to|into) your|credited)\b"#

    /// Reads the parts in any order: the amount by its money pattern, the
    /// card by card words, masked digits or `isKnownCard`, the shop from
    /// what is left. A bank's notification goes to `BankNotice` instead
    /// (`isBankNotice`): one from a bank's app always, even a short line
    /// (9 Oct 2026), and a sentence from Wallet or with no app. Wallet and
    /// no app read alike.
    /// On Wallet's short lines, `BankNotice`'s refusal phrases run first,
    /// line by line, and once there is an amount a bank's status line
    /// ("Payment received", "Low balance") is refused too (review, 8 Oct
    /// 2026), so a bank's terse alert is never logged. `bankNames`: the
    /// banks of the person's own cards, lower case. The tap fields are
    /// never looked at.
    @MainActor
    func read(isKnownCard: (String) -> Bool = { _ in false }, bankNames: Set<String> = []) -> Reading {
        let text = joined
        if isBankNotice { return BankNotice.read(text, isKnownCard: isKnownCard) }
        if let refused = BankNotice.lineRefusal(text) { return refused }
        if text.range(of: Self.notCompletedPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .notCompleted
        }
        let parts = WalletTapText.parse(text, notification: true, isKnownCard: isKnownCard)
        guard let amount = parts.amount, let value = AmountParser.parse(amount)?.amount, value > 0 else {
            return .noAmount
        }
        let rest = [subtitle, body].map(TapField.normalize).flatMap { $0.split(whereSeparator: \.isNewline).map(String.init) }
        if BankNotice.isBankStatus(title: TapField.normalize(title), rest: rest, bankNames: bankNames) { return .notAPurchase }
        let refund = text.range(of: Self.refundPattern, options: [.regularExpression, .caseInsensitive]) != nil
        if !refund, text.range(of: Self.moneyInPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .moneyIn
        }
        let signed = refund && !AmountParser.isNegative(amount) ? "-" + amount : amount
        return .payment(amount: signed, merchant: parts.merchant, card: parts.card)
    }

    static let noAmountMessage = "Sortd saw a Wallet notification with no amount."
    static let notCompletedMessage = "Sortd saw a payment that didn't go through. Nothing was logged."
    static let moneyInMessage = "Sortd saw money coming in, not a purchase. Nothing was logged."
    static let notAPurchaseMessage = "Sortd saw a bank notification that isn't a purchase. Nothing was logged."
}

/// One-field version of Log Purchase for the Wallet automation: pick the
/// Transaction once and Sortd pulls out the amount, shop and card itself.
/// Shortcuts turns the transaction into text; its exact layout isn't
/// documented, so `WalletTapText` reads it loosely.
struct LogWalletTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Wallet Tap"
    static let description = IntentDescription(
        "Logs a Wallet tap in Sortd. In a Wallet automation, set Transaction to the Shortcut Input.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Transaction", description: "The whole Wallet transaction as text, if you have it.")
    var transaction: String?

    /// iOS hands the Wallet automation a Transaction, which Shortcuts can't
    /// turn into text ("couldn't convert from Transaction to Text"). So each
    /// part can be set on its own: drag the transaction's Amount, Merchant
    /// and Card into these.
    @Parameter(title: "Amount", description: "The transaction's amount.")
    var amount: String?

    @Parameter(title: "Shop", description: "The transaction's merchant.")
    var merchant: String?

    @Parameter(title: "Card", description: "The card that was tapped.")
    var card: String?

    /// iOS 27's Notification trigger (an app or a website, as well as a
    /// till): Wallet's notification, part by part. When any of these is
    /// set, Amount, Shop, Card and Transaction are ignored.
    @Parameter(title: "Notification Title", description: "The Wallet notification's title.")
    var notificationTitle: String?

    @Parameter(title: "Notification Subtitle", description: "The Wallet notification's subtitle.")
    var notificationSubtitle: String?

    @Parameter(title: "Notification Body", description: "The Wallet notification's body.")
    var notificationBody: String?

    /// Which app sent the notification (9 Oct 2026): Wallet's is read as
    /// Wallet's, any other app's as a bank's.
    @Parameter(title: "Notification App", description: "The app that sent the notification. Set it to Notification › App.")
    var notificationApp: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) in Sortd") {
            \.$card
            \.$transaction
            \.$notificationTitle
            \.$notificationSubtitle
            \.$notificationBody
            \.$notificationApp
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await Self.performAndLog(transaction: transaction, amount: amount, merchant: merchant, card: card,
                                         notification: WalletNotification(title: notificationTitle,
                                                                          subtitle: notificationSubtitle,
                                                                          body: notificationBody,
                                                                          app: notificationApp))
        return .result(dialog: IntentDialog(stringLiteral: r.message))
    }

    /// Every step `perform()` takes, in one place: the store-can't-open
    /// fallback (#8, spec 2026-09-26) queues the already-resolved fields
    /// instead of crashing or throwing; otherwise `handle` runs and the
    /// widget is refreshed before Shortcuts ends. Never throws — `handle`'s
    /// own do/catch already turns a save failure into a queued tap, so this
    /// only guards the type system's own `throws`, keeping the promise that
    /// Shortcuts never sees a failed action.
    ///
    /// Shared with the DEBUG-only tap-replay hook in `SpendApp.swift`'s
    /// init: a replay run must go through exactly this path, store-failure
    /// fallback included, not a shortcut through `handle` alone — otherwise
    /// a replay could look healthy while a real Shortcuts run, hitting a
    /// closed store, would not be.
    ///
    /// Every run that gets here logs one `apple_pay_run` event, whatever
    /// came of it (8 Oct 2026): a run that saved nothing left no trace, so
    /// "why wasn't it logged" had no answer.
    @MainActor
    static func performAndLog(transaction: String?, amount: String?, merchant: String?, card: String?,
                             notification: WalletNotification = .init(),
                             now: Date = .now) async -> LogPurchaseIntent.Outcome {
        let outcome = await Self.performRun(transaction: transaction, amount: amount, merchant: merchant, card: card,
                                            notification: notification, now: now)
        Analytics.shared.track(.applePayRun, Self.runEvent(outcome: outcome, transaction: transaction, amount: amount,
                                                           merchant: merchant, card: card, notification: notification))
        return outcome
    }

    /// `performAndLog` without the run event, so its early returns cannot
    /// skip it.
    @MainActor
    private static func performRun(transaction: String?, amount: String?, merchant: String?, card: String?,
                                   notification: WalletNotification,
                                   now: Date) async -> LogPurchaseIntent.Outcome {
        guard case .success(let container) = SpendStore.containerForIntent() else {
            if notification.isPresent {
                // Read now, so only a real payment is queued.
                let reading = notification.read(isKnownCard: { CardBook.shared.isOneCard(named: $0) },
                                                bankNames: CardBook.shared.bankNames)
                switch reading {
                case .notCompleted, .noAmount, .moneyIn, .notAPurchase:
                    LogPurchaseIntent.recordReach(Self.record(transaction: transaction, amount: amount, merchant: merchant,
                                                              card: card, notification: notification, at: now), at: now)
                    return Self.notPaymentOutcome(reading)
                case .payment(let parsedAmount, let parsedMerchant, let parsedCard):
                    let message = await TapQueue.saveForLater(merchant: parsedMerchant, amount: parsedAmount, card: parsedCard,
                                                              date: now, trigger: notification.isBankNotice ? .bank : .notification)
                    return LogPurchaseIntent.Outcome(message: message, transaction: nil, merged: false, saveFailed: true,
                                                     kept: message != TapQueue.notSavedMessage)
                }
            }
            let resolved = Self.resolvedFields(transaction: transaction, amount: amount, merchant: merchant, card: card)
            let message = await TapQueue.saveForLater(merchant: resolved.merchant, amount: resolved.amount, card: resolved.card, date: now)
            return LogPurchaseIntent.Outcome(message: message, transaction: nil, merged: false, saveFailed: true,
                                             kept: message != TapQueue.notSavedMessage)
        }
        let outcome: LogPurchaseIntent.Outcome
        do {
            outcome = try await Self.handle(transaction, amount: amount, merchant: merchant, card: card,
                                            notificationTitle: notification.title,
                                            notificationSubtitle: notification.subtitle,
                                            notificationBody: notification.body,
                                            notificationApp: notification.app,
                                            in: container.mainContext, book: .shared, now: now)
        } catch {
            // `handle` never actually throws (its own do/catch queues
            // instead), but its signature does; a genuine surprise here
            // still must not reach Shortcuts as a failed action. Nothing
            // was queued here, so the run is lost (`kept: false`).
            outcome = LogPurchaseIntent.Outcome(message: "Saved for later. Sortd will finish it when it next opens.",
                                                transaction: nil, merged: false, saveFailed: true, kept: false)
        }
        // The app may not be running: update the widget before Shortcuts ends.
        WidgetBridge.refresh(from: container.mainContext)
        // The shortcut runs with "Show When Run" off, so the dialog is not
        // seen: say "Logged" with a notification, if already allowed.
        await LoggedNotice.post(for: outcome)
        // A second notice when this tap moves its category past 80% or 100%
        // of its limit (8 Oct 2026). Only for a saved purchase, with Category
        // Limit Alerts on, a limit on that category and notifications already
        // allowed; at most 3 a week.
        await CategoryNudge.post(for: outcome, in: container.mainContext, now: now)
        return outcome
    }

    /// Combines the free-text transaction with any fields set on their own
    /// (explicit fields win: they came straight from the transaction, not
    /// from text somebody had to format). Pure, so both `handle` and
    /// `perform`'s store-failure fallback can reuse it — a tap queued for
    /// later gets the same resolved fields it would otherwise have logged.
    ///
    /// A lone card name in the free text ("Visa Debit ••4821", known bug
    /// U6) is never accepted as a merchant: `WalletTapText.parse` has
    /// already put it in `card`, and text that only names a card is not a
    /// shop even when parsing found nothing else at all.
    nonisolated static func resolvedFields(transaction text: String?, amount: String?, merchant: String?,
                                           card: String?) -> (merchant: String?, amount: String?, card: String?) {
        var parts = WalletTapText.parse(text ?? "")
        let raw = TapField.normalize(text)
        if parts.merchant == nil, parts.amount == nil, !raw.isEmpty, !WalletTapText.looksLikeCard(raw) {
            parts.merchant = String(raw.prefix(60))
        }
        func kept(_ value: String?) -> String? {
            let normalized = TapField.normalize(value)
            return normalized.isEmpty ? nil : normalized
        }
        if let amount = kept(amount) { parts.amount = amount }
        if let merchant = kept(merchant) { parts.merchant = merchant }
        if let card = kept(card) { parts.card = card }
        return (parts.merchant, parts.amount, parts.card)
    }

    /// A notification run: any of the three notification parts is set.
    /// Then only the notification is read — the tap fields may hold stray
    /// text when this trigger fired, so they are ignored entirely. All
    /// three blank: exactly the tap behaviour from before. `queueURL` goes
    /// straight to `LogPurchaseIntent.handle` (a test's own queue file).
    @MainActor
    static func handle(_ text: String?, amount: String? = nil, merchant: String? = nil, card: String? = nil,
                       notificationTitle: String? = nil, notificationSubtitle: String? = nil,
                       notificationBody: String? = nil, notificationApp: String? = nil,
                       in context: ModelContext, book: CardBook,
                       now: Date = .now, debugForceSaveFailure: Bool = false,
                       queueURL: URL? = nil) async throws -> LogPurchaseIntent.Outcome {
        let notification = WalletNotification(title: notificationTitle, subtitle: notificationSubtitle, body: notificationBody,
                                              app: notificationApp)
        let record = Self.record(transaction: text, amount: amount, merchant: merchant, card: card,
                                 notification: notification, at: now)
        let result: LogPurchaseIntent.Outcome
        let shop: String?
        if notification.isPresent {
            let reading = notification.read(isKnownCard: { book.isOneCard(named: $0) }, bankNames: book.bankNames)
            switch reading {
            case .notCompleted, .noAmount, .moneyIn, .notAPurchase:
                // Shortcuts reached Sortd, but there is nothing to save:
                // never a "needs a check" row for a boarding pass or a
                // bank's balance alert.
                LogPurchaseIntent.recordReach(record, at: now)
                return Self.notPaymentOutcome(reading)
            case .payment(let parsedAmount, let parsedMerchant, let parsedCard):
                shop = parsedMerchant
                // A bank app's sentence is its own trigger, so it can pair
                // with the tap and with Wallet's notification of the same
                // purchase (8 Oct 2026).
                let trigger: TapTrigger = notification.isBankNotice ? .bank : .notification
                result = try await LogPurchaseIntent.handle(merchant: parsedMerchant, amount: parsedAmount, card: parsedCard,
                                                            in: context, book: book, now: now,
                                                            debugForceSaveFailure: debugForceSaveFailure,
                                                            trigger: trigger, record: record, seen: notification.seen,
                                                            queueURL: queueURL)
            }
        } else {
            let resolved = resolvedFields(transaction: text, amount: amount, merchant: merchant, card: card)
            shop = resolved.merchant
            result = try await LogPurchaseIntent.handle(merchant: resolved.merchant, amount: resolved.amount,
                                                        card: resolved.card, in: context, book: book, now: now,
                                                        debugForceSaveFailure: debugForceSaveFailure, record: record,
                                                        queueURL: queueURL)
        }
        // A real Wallet tap reached the app and was kept (a ▶ test run has no
        // purchase; a legacy "Send a Test Tap" row is not a real tap).
        if result.transaction != nil, shop != LogPurchaseIntent.legacyTestMerchant {
            Analytics.shared.track(.applePayTapLogged, ["merged": .bool(result.merged)])
        }
        return result
    }

    /// The "last tap received" line: which kind of run it was and how each
    /// field arrived (empty, a placeholder, or how long), tap fields and
    /// notification parts both (on a notification run the tap fields are
    /// ignored, but whether they were filled is the thing to check on a
    /// phone). Never the words: the shop, the amount and the card would stay
    /// in the app's defaults after the purchase is deleted (X5, 3 Oct 2026).
    nonisolated static func record(transaction: String?, amount: String?, merchant: String?, card: String?,
                                   notification: WalletNotification, at now: Date) -> String {
        let kind = notification.isPresent ? "notification run" : "tap run"
        var fields = "amount \(TapField.shape(amount)) · merchant \(TapField.shape(merchant)) · card \(TapField.shape(card))"
        if !TapField.isBlank(transaction) { fields += " · text \(TapField.shape(transaction))" }
        return "\(now.formatted(date: .abbreviated, time: .standard)): \(kind) · \(fields) · \(notification.shape)"
    }

    /// Nothing saved: say which kind of notification it was.
    private static func notPaymentOutcome(_ reading: WalletNotification.Reading) -> LogPurchaseIntent.Outcome {
        let message = switch reading {
        case .notCompleted: WalletNotification.notCompletedMessage
        case .moneyIn: WalletNotification.moneyInMessage
        case .notAPurchase: WalletNotification.notAPurchaseMessage
        default: WalletNotification.noAmountMessage
        }
        return LogPurchaseIntent.Outcome(message: message, transaction: nil, merged: false, dropped: reading)
    }

    /// The `apple_pay_run` properties for one run: what kind it was ("tap",
    /// "notification" for Wallet's, "bank" for one from a bank's app or read as a bank's sentence), what
    /// came of it, and which fields arrived. Fixed words and booleans only,
    /// never an amount, a shop or a card name. The `has_*` flags are the
    /// fields as they arrived, before any parsing; `has_app` is Notification ›
    /// App (9 Oct 2026); `has_text` is the old
    /// free-text `transaction` field.
    @MainActor
    static func runEvent(outcome: LogPurchaseIntent.Outcome, transaction: String?, amount: String?, merchant: String?,
                         card: String?, notification: WalletNotification) -> [String: Analytics.AnalyticsValue] {
        let result: String
        if outcome.saveFailed {
            result = outcome.kept ? "queued" : "not_saved"
        } else if let dropped = outcome.dropped, let word = Self.droppedWord(dropped) {
            result = word
        } else if outcome.transaction?.rawMerchant == ApplePayHealthCheck.merchant {
            // "Check the Shortcut" (`ApplePaySetupPanel`): not a purchase.
            result = "health_check"
        } else if outcome.refund {
            result = "refund"
        } else if let t = outcome.transaction {
            if outcome.merged {
                result = "merged"
            } else if t.needsCheck || t.lacksShop || t.amount <= 0 {
                result = "needs_check"
            } else {
                result = "saved"
            }
        } else {
            result = "blank"
        }
        return [
            "kind": .string(!notification.isPresent ? "tap" : notification.isBankNotice ? "bank" : "notification"),
            "result": .string(result),
            "has_amount": .bool(!TapField.isBlank(amount)),
            "has_shop": .bool(!TapField.isBlank(merchant)),
            "has_card": .bool(!TapField.isBlank(card)),
            "has_app": .bool(!TapField.isBlank(notification.app)),
            "has_title": .bool(!TapField.isBlank(notification.title)),
            "has_subtitle": .bool(!TapField.isBlank(notification.subtitle)),
            "has_body": .bool(!TapField.isBlank(notification.body)),
            "has_text": .bool(!TapField.isBlank(transaction)),
        ]
    }

    /// Why a notification run saved nothing, as the event's word. A payment
    /// is never dropped, so it has none.
    private static func droppedWord(_ reading: WalletNotification.Reading) -> String? {
        switch reading {
        case .notCompleted: "not_completed"
        case .noAmount: "no_amount"
        case .moneyIn: "money_in"
        case .notAPurchase: "not_purchase"
        case .payment: nil
        }
    }
}

/// Splits the text Shortcuts makes from a Wallet transaction into amount,
/// merchant and card. Pure, so it's tested.
nonisolated enum WalletTapText {
    struct Parts: Equatable { var amount: String?; var merchant: String?; var card: String? }

    /// `notification`: the text is Wallet's own notification (Title,
    /// Subtitle and Body joined by newlines), so framing words around the
    /// shop ("You paid", "paid to", "Refund from", "Apple Pay") are dropped
    /// too, and a line naming one of the person's own cards
    /// (`isKnownCard`, a `CardBook` match) is the card even with no card
    /// word in it ("YouTrip"). Off, the tap text reads exactly as before.
    static func parse(_ text: String, notification: Bool = false,
                      isKnownCard: (String) -> Bool = { _ in false }) -> Parts {
        // Fields may come one per line, as "Key: value" pairs, or on one
        // line separated by commas.
        var lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count == 1, lines[0].contains(", ") {
            lines = lines[0].components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var parts = Parts()
        var rest: [String] = []
        // A shop word that is also a currency code, before a number ("TOP
        // 10 PIZZA"), is only a guess at the amount: a real one elsewhere,
        // with a sign or cents ("A$23.50"), wins.
        let hasClearAmount = lines.contains { line in
            !looksLikeDate(line) && money(in: withoutClockTimes(line)).map(isClearAmount) == true
        }
        for line in lines {
            // A whole line that is only a Shortcuts placeholder (an unfilled
            // Title/Subtitle/Body, spec 2026-09-26 failsafe #13) is not a
            // shop, a card or an amount — treat it as if the line were
            // never there, not as text to guess a merchant from.
            if TapField.isBlank(line) { continue }
            if let (key, value) = keyValue(line) {
                if TapField.isBlank(value) { continue }
                switch key {
                case "amount": parts.amount = value; continue
                case "merchant": parts.merchant = value; continue
                case "card", "card or pass", "pass": parts.card = value; continue
                case "name", "transaction", "date", "time": continue
                default: break
                }
            }
            if looksLikeDate(line) { continue }
            // "Coles A$23.50 9:41 am NAB Visa Debit": the time is not part of
            // the shop or the card.
            let line = withoutClockTimes(line)
            if line.isEmpty { continue }
            if parts.amount == nil, let money = money(in: line), !hasClearAmount || isClearAmount(money) {
                parts.amount = money
                // "Seven Seeds A$4.50 NAB Visa Debit": keep what's around it.
                let leftover = line.replacingOccurrences(of: money, with: "\n")
                    .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                rest.append(contentsOf: leftover.flatMap(splitIntoCandidates))
            } else if notification, !splitIntoCandidates(line).contains(where: looksLikeCard) {
                // A notification's own line with no amount is one name
                // ("Cafe on Collins"), not prose to cut at "on". Only a
                // card glued on with a joining word is split off.
                rest.append(line)
            } else {
                rest.append(contentsOf: splitIntoCandidates(line))
            }
        }
        if notification { rest = rest.compactMap(withoutNotificationFiller) }
        // The card is the last line that names a card; the shop is the first other one.
        if parts.card == nil, let i = rest.lastIndex(where: looksLikeCard) { parts.card = rest.remove(at: i) }
        if notification, parts.card == nil, let i = rest.lastIndex(where: isKnownCard) { parts.card = rest.remove(at: i) }
        if parts.merchant == nil, let first = rest.first { parts.merchant = first }
        return parts
    }

    /// Joining words a one-line prose transaction ("A$5.50 at Seven Seeds
    /// with NAB Visa Debit", a bank app's own alert text) glues a real shop
    /// name to. Without splitting on these, the whole trailing phrase reads
    /// as one candidate and — the moment any word in it (like "Visa")
    /// `looksLikeCard` — the shop name is swallowed whole into the card
    /// field along with it and lost (ApplePayHunt items 7/8).
    private static let connectorWords = ["at", "with", "from", "on", "via", "using", "for"]

    /// A bank app's own framing text ("You spent", "You paid…") is never a
    /// shop name, even once it's on its own with nothing else nearby
    /// (ApplePayHunt item 2).
    private static let nonShopPhrases: Set<String> = [
        "you spent", "you paid", "payment of", "spent", "paid", "transaction of", "purchase of",
    ]

    /// Splits one leftover fragment into shop/card candidates: cut on any
    /// connector word at a word boundary (case-insensitive), trim, drop
    /// empty pieces and known non-shop filler phrases. A fragment with no
    /// connector word in it and no filler phrase passes through unchanged
    /// — this must not disturb the existing one-piece-per-line behaviour.
    private static func splitIntoCandidates(_ text: String) -> [String] {
        let pattern = "\\b(?:" + connectorWords.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [text] }
        let ns = text as NSString
        let replaced = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "\n")
        return replaced.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !nonShopPhrases.contains($0.lowercased()) }
    }

    /// Words Wallet's notification may put around a shop name. Only ever
    /// dropped at the start ("You paid DoorDash", "Refund from…" once
    /// "from" has split it off) or the end ("DoorDash refund").
    private static let leadingFiller: Set<String> = [
        "you", "you've", "have", "has", "just", "paid", "spent", "sent", "payment", "purchase", "charged",
        "made", "refund", "refunded", "received", "to",
    ]
    /// Dropped only straight after a leading filler word ("paid to", "a
    /// payment of"), never at the start of a name on its own ("A Little Cafe").
    private static let followingFiller: Set<String> = ["a", "an", "of", "at", "your", "from"]
    private static let trailingFiller: Set<String> = ["refund", "refunded", "payment", "purchase"]
    /// Whole lines that name Wallet itself, never a shop. `BankNotice` reads
    /// one as "this notification is Wallet's".
    static let walletNames: Set<String> = ["apple pay", "wallet", "apple wallet", "apple cash"]

    /// A bank's heading, never a shop: "Purchase alert" read as the shop
    /// "alert" once "purchase" was dropped as filler (review, 8 Oct 2026).
    private static let alertNames: Set<String> = ["purchase alert", "transaction alert", "card alert", "payment alert"]

    /// One shop/card candidate from a notification with its framing words
    /// and stray punctuation removed, or nil when nothing is left.
    private static func withoutNotificationFiller(_ candidate: String) -> String? {
        let whole = candidate.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ".,;:!·-–—|"))).lowercased()
        if alertNames.contains(whole) { return nil }
        var words = candidate.split(separator: " ").map(String.init)
        var dropped = false
        while let first = words.first?.lowercased(),
              leadingFiller.contains(first) || (dropped && followingFiller.contains(first)) {
            words.removeFirst()
            dropped = true
        }
        while let last = words.last?.lowercased(), trailingFiller.contains(last) { words.removeLast() }
        let joined = words.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ".,;:!·-–—|")))
        guard !joined.isEmpty, !walletNames.contains(joined.lowercased()) else { return nil }
        // Nothing but punctuation ("·", "…") is not a name; an emoji is kept.
        guard joined.unicodeScalars.contains(where: { !CharacterSet.punctuationCharacters.contains($0) }) else { return nil }
        guard !nonShopPhrases.contains(joined.lowercased()) else { return nil }
        return joined
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard key.count <= 14, !key.contains(where: \.isNumber), !value.isEmpty else { return nil }
        return (key, value)
    }

    /// A money amount inside the text: a currency sign or code next to the
    /// number, or a number with cents. "Cafe 21" and "Zone 3" are not money.
    static func money(in s: String) -> String? {
        let sign = #"(?:-|−)?"#
        // "CN¥" before the bare "¥" alternative, so yuan keep their "CN" and
        // aren't cut down to a yen sign. "JP¥" (how en_GB and en_SG phones
        // write yen) is listed too: the bare "¥" can't start inside a word.
        let marker = #"(?:[A-Z]{0,2}\$|CN¥|JP¥|€|£|¥|₹|฿|₱|₩|₪|RM|Rs\.?|[A-Z]{3})"#
        // Grouped thousands ("1,234.50", "1.234,50") or a plain run of digits
        // ("1234.50" — the old pattern stopped at 3 digits and read A$123).
        // A group is exactly 3 digits: "A$45 1234" is A$45, not A$45 123.
        let number = #"(?:\d{1,3}(?:[,.\s]\d{3})+(?!\d)|\d+)(?:[.,]\d{2})?"#
        let patterns = [
            // Not inside a word: "PANTRY 24" is not 24 Turkish lira.
            #"(?<![A-Za-z])"# + sign + marker + #"\s?"# + number, // A$4.50, SGD 6.20, -$5
            sign + number + #"\s?(?:[A-Z]{3})\b"#,             // 6.20 SGD
            // 4.50, 1,234.50 — the whole number, not "234.50" out of it.
            sign + #"(?<![\d.,])(?:\d{1,3}(?:,\d{3})+|\d+)[.,]\d{2}\b"#,
        ]
        let ns = s as NSString
        // A code and a whole number ("TOP 10") is kept only if nothing
        // clearer (a sign or cents) is in the text.
        var guess: String?
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            // Every match, not just the first: in "NAB 4821 A$4.50" the first
            // hit ("NAB 4821") is rejected and the real amount comes after it.
            for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let hit = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                // A bare code must be a real currency ("THB 120", not "ABC 12").
                if let code = hit.uppercased().split(whereSeparator: { !$0.isLetter }).first, code.count == 3,
                   !hit.contains("$"), AmountParser.currency(in: String(code)) == nil { continue }
                if isClearAmount(hit) { return hit }
                if guess == nil { guess = hit }
            }
        }
        return guess
    }

    static func looksLikeCard(_ s: String) -> Bool {
        let words = Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: ["card", "visa", "mastercard", "amex", "debit", "credit", "eftpos", "unionpay", "rupay"]) {
            return true
        }
        // "••4821", "…4821", "*4821": a masked card number.
        return s.range(of: #"[•·…*]\s?\d{4}\b"#, options: .regularExpression) != nil
    }

    /// A line that is a date or a time, so neither the shop nor the card. A
    /// clock time counts only when no amount is on the line too: one-line
    /// tap text ("Coles A$23.50 9:41 am NAB Visa Debit") is the whole
    /// purchase, not a date.
    static func looksLikeDate(_ s: String) -> Bool {
        if s.range(of: #"^\d{1,2}[ /.-](\d{1,2}|[A-Za-z]{3,9})[ /.-]\d{2,4}|^\d{4}-\d{2}-\d{2}"#,
                   options: .regularExpression) != nil { return true }
        return s.range(of: clockTime, options: .regularExpression) != nil && money(in: withoutClockTimes(s)) == nil
    }

    /// "9:41", "9:41 am", "21:05:33", "9:41 p.m.".
    private static let clockTime = #"\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?[Mm]\b\.?)?"#

    /// The line with any clock time taken out and the spaces tidied.
    static func withoutClockTimes(_ s: String) -> String {
        s.replacingOccurrences(of: clockTime, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// An amount with a currency sign or cents ("A$23.50", "SGD 6.20",
    /// "4.50", "RM12"), not just a three-letter word and a whole number
    /// ("TOP 10", which may be a shop's name).
    static func isClearAmount(_ hit: String) -> Bool {
        if hit.unicodeScalars.contains(where: { $0.properties.generalCategory == .currencySymbol }) { return true }
        if hit.range(of: #"\d[.,]\d{2}(?!\d)"#, options: .regularExpression) != nil { return true }
        let marker = hit.trimmingCharacters(in: CharacterSet(charactersIn: "-−")).prefix(2)
        return marker == "RM" || marker == "Rs"
    }
}
