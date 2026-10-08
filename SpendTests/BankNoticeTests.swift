import Testing
import Foundation
@testable import Spend

/// A bank app's own notification (8 Oct 2026, spec
/// `2026-10-03-bank-app-notifications.md`): a sentence, not Wallet's short
/// lines. `BankNotice` is pure, so none of these touch a store. The sample
/// texts are made up to look like bank notices; real wording comes from a
/// phone test.
struct BankNoticeTests {
    private typealias Reading = WalletNotification.Reading

    private func payment(_ text: String, isKnownCard: (String) -> Bool = { _ in false }) -> (amount: String, merchant: String?, card: String?)? {
        if case .payment(let amount, let merchant, let card) = BankNotice.read(text, isKnownCard: isKnownCard) {
            return (amount, merchant, card)
        }
        return nil
    }

    // MARK: - Sentence or Wallet's short lines

    @Test func walletShortLinesAreNotASentence() {
        #expect(!BankNotice.isSentence("NAB Visa Debit\nDoorDash\nA$23.40"))
        #expect(BankNotice.isSentence("You spent $23.40 at DOORDASH with your card ending 4821."))
    }

    // MARK: - Purchases

    @Test func commBankSpent() {
        #expect(BankNotice.read("You spent $23.40 at DOORDASH with your card ending 4821.")
                == .payment(amount: "$23.40", merchant: "DOORDASH", card: "4821"))
    }

    @Test func dbsTransaction() {
        #expect(BankNotice.read("A transaction of SGD 31.80 was made with your DBS card ending 1234 at UBER EATS on 03 Oct.")
                == .payment(amount: "SGD 31.80", merchant: "UBER EATS", card: "1234"))
    }

    @Test func purchaseOf() {
        #expect(BankNotice.read("Purchase of AUD 5.50 at Seven Seeds Carlton")
                == .payment(amount: "AUD 5.50", merchant: "Seven Seeds Carlton", card: nil))
    }

    @Test func cardPurchaseTo() {
        let r = payment("Card purchase: $12.00 to NETFLIX.COM")
        #expect(r?.amount == "$12.00")
        #expect(r?.merchant == "NETFLIX.COM")
    }

    @Test func hungryJacksWithMaskedCard() {
        #expect(BankNotice.read("You spent $11.95 at HUNGRY JACKS CARLTON using your Debit Mastercard •••• 4821")
                == .payment(amount: "$11.95", merchant: "HUNGRY JACKS CARLTON", card: "4821"))
    }

    @Test func nabPurchaseWithState() {
        let r = payment("Purchase of $12.50 at SUBWAY CARLTON VIC")
        #expect(r?.amount == "$12.50")
        #expect(r?.merchant == "SUBWAY CARLTON VIC")
    }

    @Test func anzSpentAfterAmount() {
        #expect(BankNotice.read("$23.40 spent at UBER* TRIP with card ending in 4821")
                == .payment(amount: "$23.40", merchant: "UBER* TRIP", card: "4821"))
    }

    @Test func usedAt() {
        #expect(BankNotice.read("Your card ending 4821 was used at WOOLWORTHS for $45.20")
                == .payment(amount: "$45.20", merchant: "WOOLWORTHS", card: "4821"))
    }

    @Test func ptyLtdAndFullStopTrimmed() {
        let r = payment("You paid $8.00 to SEVEN SEEDS PTY LTD.")
        #expect(r?.amount == "$8.00")
        #expect(r?.merchant == "SEVEN SEEDS")
    }

    @Test func knownCardNameIsTheCard() {
        let r = payment("You spent $5.50 at Seven Seeds with YouTrip", isKnownCard: { $0.lowercased().contains("youtrip") })
        #expect(r?.amount == "$5.50")
        #expect(r?.merchant == "Seven Seeds")
        #expect(r?.card?.lowercased() == "youtrip")
    }

    // MARK: - Not a purchase

    @Test func otpIsNotAPurchase() {
        #expect(BankNotice.read("Your OTP is 482193. Do not share it. Amount SGD 31.80 at UBER") == .notAPurchase)
    }

    @Test func receivedIsMoneyIn() {
        #expect(BankNotice.read("You received $50.00 from J TAN via PayID") == .moneyIn)
    }

    @Test func balanceIsNotAPurchase() {
        #expect(BankNotice.read("Your available balance is $1,204.11") == .notAPurchase)
    }

    @Test func declinedIsNotCompleted() {
        #expect(BankNotice.read("Payment of $23.40 to DOORDASH was declined") == .notCompleted)
    }

    @Test func refundIsANegativePayment() {
        #expect(BankNotice.read("Refund of $23.40 from DOORDASH")
                == .payment(amount: "-$23.40", merchant: "DOORDASH", card: nil))
    }

    @Test func cashbackIsNotAPurchase() {
        #expect(BankNotice.read("Get $20 cashback when you spend $100 at Myer") == .notAPurchase)
    }

    @Test func billDueIsNotAPurchase() {
        #expect(BankNotice.read("Your credit card payment of $500.00 is due on 12 Oct") == .notAPurchase)
    }

    @Test func amountWithoutSpendWordIsNotAPurchase() {
        #expect(BankNotice.read("Your limit is now $2,000.00 at your request") == .notAPurchase)
    }

    // MARK: - Review, 8 Oct 2026: sentences that are not spending

    @Test(arguments: [
        "We paid you $25.00 interest",
        "J TAN paid you $50.00",
        "J TAN paid $50.00 into your account",
        "A payment of $50.00 from J TAN has arrived",
    ])
    func moneyComingInIsMoneyIn(_ text: String) {
        #expect(BankNotice.read(text) == .moneyIn)
    }

    @Test(arguments: [
        "You paid $500.00 to your credit card ending 4821",
        "We've paid $200.00 from your Everyday account to your Savings account",
        "You paid $200.00 to ANZ Savings ending 4821",
        "Your card payment of $500.00 has been processed",
    ])
    func movingMoneyBetweenYourOwnAccountsIsNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test(arguments: [
        "Your card limit was increased to $2,000. Spend responsibly.",
        "Spending alert: you've spent $500.00 this week",
        "You've spent $1,200 this month. That's 80% of your budget",
    ])
    func limitsAndSpendingTotalsAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test(arguments: [
        "Spend $50 at Woolworths this week and get 10% back",
        "Spend $100 or more at Myer to earn 2,000 bonus points",
        "Earn double points when you spend $30 at Coles",
        "Last chance! Spend $20 at Uber Eats and save",
    ])
    func offersAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test(arguments: [
        "Your NetCode is 482193 for a payment of $31.80 to UBER",
        "Your code is 482193 to approve a $31.80 purchase at UBER",
        "Use 482193 to confirm your payment of $31.80 to UBER. Never share this code.",
        "Approve your purchase of $31.80 at UBER in the CommBank app",
        "Did you just try to make a purchase of $31.80 at UBER? Open the app to approve",
        "Your card was charged $1.00 to verify it by APPLE.COM",
    ])
    func codesAndApprovalsAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test(arguments: [
        "Payment of $500 due 12 Oct",
        "Make a payment of $35 by 12 Oct to avoid late fees",
        "Your bill of $89.00 will be paid on 15 Oct",
        "Your scheduled payment of $200.00 to J Smith will be paid tomorrow",
        "Your $500.00 payment to TELSTRA is scheduled",
        "Autopay: $500.00 will be paid from your account on 12 Oct",
        "You will be charged $15.99 by NETFLIX on 12 Oct",
    ])
    func billsAndPaymentsToComeAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test(arguments: [
        "Transaction of $23.40 at DOORDASH was reversed",
        "Your $23.40 purchase at DOORDASH was cancelled",
        "A pending transaction of $23.40 at DOORDASH",
    ])
    func reversedCancelledAndPendingAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    @Test func aBlockedTransactionIsNotCompleted() {
        #expect(BankNotice.read("We blocked a transaction of $999.00 at XYZ STORE on card ending 4821") == .notCompleted)
    }

    @Test func aSpendSentenceWithNoShopIsNotAPurchase() {
        #expect(BankNotice.read("You spent $23.40 with your card ending 4821") == .notAPurchase)
    }

    /// A second amount means it is not one purchase, unless it is the balance.
    @Test func aSecondAmountIsNotAPurchaseUnlessItIsTheBalance() {
        #expect(BankNotice.read("You spent $23.40 at DOORDASH and $5.00 at UBER") == .notAPurchase)
        #expect(BankNotice.read("You spent $23.40 at DOORDASH. Available balance $976.60")
                == .payment(amount: "$23.40", merchant: "DOORDASH", card: nil))
    }

    // MARK: - Review, 8 Oct 2026: where the shop's name ends

    @Test(arguments: [
        "You spent $23.40 at DOORDASH in Carlton",
        "Purchase of $23.40 at DOORDASH has been approved",
        "Purchase of $23.40 at DOORDASH will appear on your statement",
        "Purchase of $23.40 at DOORDASH \u{2014} balance $976.60",
        "You spent $23.40 at DOORDASH balance $976.60",
        "You spent $23.40 at DOORDASH? Not you? Call us",
    ])
    func theShopStopsWhereTheSentenceMovesOn(_ text: String) {
        #expect(payment(text)?.merchant == "DOORDASH")
    }

    @Test func aShopThatRefundedIsTheShop() {
        #expect(BankNotice.read("DOORDASH refunded $5.00 to your card ending 4821")
                == .payment(amount: "-$5.00", merchant: "DOORDASH", card: "4821"))
    }

    // MARK: - Review round 2, 8 Oct 2026

    @Test(arguments: [
        "Your payment of $89.00 to TELSTRA will be made tomorrow",
        "Your $15.99 payment to NETFLIX is coming up on 12 Oct",
        "Heads up: a payment of $15.99 to NETFLIX goes out tomorrow",
        "Confirm your payment of €31.80 at UBER",
        "Your card payment of S$45.00 to SHOPEE requires authentication",
        "Your transaction of S$80.00 at ZARA was voided",
        "Payment to Amazon of €23.40 was reverted",
        "You've paid $500.00 to ANZ Credit Card ending 4821",
        "You paid $400.00 to NAB Low Rate Card",
    ])
    func paymentsToComeUndoneOrToYourOwnCardAreNotAPurchase(_ text: String) {
        #expect(BankNotice.read(text) == .notAPurchase)
    }

    /// "in", "is", "and", "of" and "balance" end a shop's name only as
    /// sentence words, never inside the name.
    @Test(arguments: [
        ("You spent $30.00 at The Balance Yoga Studio", "The Balance Yoga Studio"),
        ("Purchase of $12.00 at Bread In Common", "Bread In Common"),
        ("Purchase of $8.00 at House Of Pho", "House Of Pho"),
        ("You spent $5.50 at Starbucks and earned 4 points", "Starbucks"),
        ("Purchase of $9.00 at KMART of Carlton", "KMART"),
    ])
    func sentenceWordsEndTheShopButNamesKeepTheirWords(_ text: String, _ shop: String) {
        #expect(payment(text)?.merchant == shop)
    }
}

