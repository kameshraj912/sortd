import Testing
import Foundation
@testable import Spend

/// Bank alert emails.
///
/// The samples below are written in the shapes bank alerts take, not copied
/// from verified emails, so these tests prove the reader handles those
/// shapes — not that any particular bank words things this way. Real emails
/// from NAB and the rest still need checking against this.
///
/// Most of these tests are about what must *not* become a purchase. A missed
/// alert is an annoyance. An invented one puts a number in front of somebody
/// that they can't explain, and then they stop believing any of the numbers.
struct BankAlertTests {

    private func bank(_ domain: String = "nab.com.au", _ currency: String = "AUD") -> BankAlerts.Bank {
        BankAlerts.Bank(name: "Test", domain: domain, currency: currency)
    }

    private func read(_ subject: String, _ body: String = "",
                      _ b: BankAlerts.Bank? = nil) -> BankAlerts.Reading? {
        BankAlerts.read(subject: subject, body: body, bank: b ?? bank())
    }

    // MARK: Senders

    @Test func recognisesTheBanksItKnows() {
        #expect(BankAlerts.bank(for: "alerts@nab.com.au")?.currency == "AUD")
        #expect(BankAlerts.bank(for: "NoReply@commbank.com.au")?.name == "CommBank")
        #expect(BankAlerts.bank(for: "ibanking.alert@dbs.com")?.currency == "SGD")
        #expect(BankAlerts.bank(for: "alert@uob.com.sg")?.currency == "SGD")
        #expect(BankAlerts.bank(for: "someone@gmail.com") == nil)
        #expect(BankAlerts.bank(for: "newsletter@notabank.com") == nil)
    }

    @Test func theGmailQueryAsksForEveryBank() {
        #expect(BankAlerts.gmailTerms.count == BankAlerts.known.count)
        #expect(BankAlerts.gmailTerms.contains("from:nab.com.au"))
        #expect(EmailParsers.gmailQuery.contains("from:nab.com.au"))
        // And the ones that were already there survived.
        #expect(EmailParsers.gmailQuery.contains("from:alerts.sg@sc.com"))
    }

    // MARK: Reading a purchase

    @Test func readsAPlainPurchaseAlert() throws {
        let r = try #require(read("Transaction alert",
                                  "A purchase of $58.30 was made at WOOLWORTHS 3342 on your card ending 1234."))
        #expect(r.amount == "58.30")
        #expect(r.currency == "AUD")
        #expect(r.merchant == "WOOLWORTHS 3342")
        #expect(r.last4 == "1234")
        #expect(!r.isRefund)
    }

    @Test func aWordBeforeTheAmountIsNotACurrency() throws {
        // Bug-hunt M1: "for" was read as currency "FOR", so the purchase counted as 0.
        for body in ["You made a payment for $58.30 at WOOLWORTHS 3342 with card ending 1234.",
                     "YOU MADE A PAYMENT FOR $58.30 AT WOOLWORTHS 3342 WITH CARD ENDING 1234."] {
            let r = try #require(read("Transaction alert", body))
            #expect(r.amount == "58.30")
            #expect(r.currency == "AUD")
        }
    }

    @Test func aShopNameOrFooterDoesNotHideAPurchase() throws {
        // Bug-hunt M3: "otp" inside HOTPOT, and footers, threw real alerts away.
        let r = try #require(read("Transaction alert", "A purchase of $42.00 was made at HOTPOT CITY on your card ending 1234."))
        #expect(r.merchant.contains("HOTPOT"))
        let footer = "A purchase of $58.30 was made at COLES 0712 on your card ending 1234.\n\n"
            + String(repeating: "Thank you for banking with us. ", count: 12)
            + "Never share your password. Read our privacy policy and terms and conditions."
        #expect(read("Transaction alert", footer)?.amount == "58.30")
        // Still rejected when the subject says so.
        #expect(read("Your one-time password", "Your OTP is 123456. Do not share it.") == nil)
    }

    @Test func readsTheOtherWordingsBanksUse() throws {
        let samples = [
            "You spent A$58.30 at WOOLWORTHS 3342 using card ending 1234.",
            "Purchase of AUD 58.30 at WOOLWORTHS 3342 with card ****1234.",
            "Card xx1234: $58.30 at WOOLWORTHS 3342 on 01/09/2026.",
            "Merchant: WOOLWORTHS 3342\nAmount: $58.30\nCard ending 1234",
        ]
        for sample in samples {
            let r = try #require(read("Transaction alert", sample), "failed on: \(sample)")
            #expect(r.amount == "58.30", "amount wrong for: \(sample)")
            #expect(r.merchant.contains("WOOLWORTHS"), "merchant wrong for: \(sample)")
            #expect(r.last4 == "1234", "last4 wrong for: \(sample)")
        }
    }

    @Test func usesTheBanksCurrencyWhenTheEmailOmitsOne() throws {
        let sg = try #require(read("Alert", "Purchase of $22.10 at NTUC FAIRPRICE.",
                                   bank("dbs.com", "SGD")))
        #expect(sg.currency == "SGD")
        #expect(sg.amount == "22.10")
    }

    @Test func aStatedCurrencyBeatsTheBanksDefault() throws {
        let r = try #require(read("Alert", "Purchase of USD 12.99 at SOME US SHOP.",
                                  bank("nab.com.au", "AUD")))
        #expect(r.currency == "USD")
    }

    @Test func readsThousands() throws {
        let r = try #require(read("Alert", "Purchase of $1,299.00 at JB HI-FI on card ending 1234."))
        #expect(r.amount == "1299.00")
    }

    // MARK: Money coming back

    @Test func aRefundIsNotSpending() throws {
        let r = try #require(read("Refund processed",
                                  "A refund of $38.00 from KMART ONLINE has been credited to your card ending 1234."))
        #expect(r.isRefund)
        #expect(r.amount == "38.00")
    }

    @Test func aReversalIsARefundToo() throws {
        let r = try #require(read("Transaction reversed",
                                  "Your transaction of $42.15 at DOORDASH has been reversed."))
        #expect(r.isRefund)
    }

    // MARK: The important half — what must never become a purchase

    @Test func aBalanceAlertIsNotAPurchase() {
        #expect(read("Balance alert", "Your balance is $1,204.55 as at 01/09/2026.") == nil)
        #expect(read("Low balance warning", "Your account balance has fallen below $100.00.") == nil)
    }

    @Test func aStatementNoticeIsNotAPurchase() {
        #expect(read("Your statement is ready",
                     "Your statement is ready. Closing balance $1,204.55. Minimum payment $25.00.") == nil)
    }

    @Test func aPaymentDueNoticeIsNotAPurchase() {
        #expect(read("Payment is due",
                     "Your minimum payment of $25.00 is due on 15/09/2026.") == nil)
    }

    @Test func aSecurityEmailIsNotAPurchase() {
        #expect(read("Security alert", "A new device logged in to your account.") == nil)
        #expect(read("One-time password", "Your one-time password is 482913. Do not share it.") == nil)
    }

    @Test func salaryGoingInIsNotAPurchase() {
        #expect(read("Deposit", "A salary payment of $3,200.00 has been credited to your account.") == nil)
    }

    @Test func anAmountWithNoMerchantIsNotAPurchase() {
        #expect(read("Alert", "A transaction of $58.30 was made on your card ending 1234.") == nil)
    }

    @Test func aMerchantWithNoAmountIsNotAPurchase() {
        #expect(read("Alert", "A purchase was made at WOOLWORTHS 3342.") == nil)
    }

    @Test func aWholeDollarAmountIsIgnored() {
        // "$58" with no cents is far more often a limit or a balance than a
        // purchase, and a wrong number is worse than a missing one.
        #expect(read("Alert", "A purchase of $58 was made at WOOLWORTHS.") == nil)
    }

    @Test func theBankTalkingAboutItselfIsNotAMerchant() {
        #expect(read("Alert", "A payment of $58.30 was made to your credit card.") == nil)
        #expect(read("Alert", "$58.30 transferred to your savings account.") == nil)
    }

    // MARK: Tidying

    @Test func merchantStopsBeforeTheNextClause() {
        #expect(BankAlerts.merchant(in: "at COLES EXPRESS on 01/09/2026") == "COLES EXPRESS")
        #expect(BankAlerts.merchant(in: "at SEVEN SEEDS using card 1234") == "SEVEN SEEDS")
        #expect(BankAlerts.merchant(in: "at UBER *EATS. Card ending 1234") == "UBER *EATS")
    }

    @Test func hardWrapsAndOddSpacesDoNotBreakIt() throws {
        let wrapped = "A purchase of $58.30 was made\nat WOOLWORTHS 3342\u{00A0}on your card   ending 1234."
        let r = try #require(read("Alert", wrapped))
        #expect(r.amount == "58.30")
        #expect(r.merchant.contains("WOOLWORTHS"))
        #expect(r.last4 == "1234")
    }

    @Test func tidyFlattensWhitespace() {
        #expect(BankAlerts.tidy("a\u{00A0}b   c\r\nd") == "a b c\nd")
    }
}

/// The bank alert reaching the rest of the app through the normal pipeline.
struct BankAlertPipelineTests {

    private func message(_ from: String, _ subject: String, _ body: String) -> EmailParsers.Message {
        EmailParsers.Message(id: "m1", from: from, subject: subject, body: body, date: .now)
    }

    @Test func aBankAlertBecomesAPurchaseRecord() throws {
        let records = EmailParsers.parse(message(
            "alerts@nab.com.au", "Transaction alert",
            "A purchase of $58.30 was made at WOOLWORTHS 3342 on your card ending 1234."))
        let r = try #require(records.first)
        #expect(r.kind == "purchase")
        #expect(r.amount == "58.30")
        #expect(r.currency == "AUD")
        #expect(r.last4 == "1234")
        #expect(r.merchant.lowercased().contains("woolworths"))
    }

    @Test func aBankRefundBecomesARefundRecord() throws {
        let records = EmailParsers.parse(message(
            "alerts@nab.com.au", "Refund",
            "A refund of $38.00 from KMART has been credited to your card ending 1234."))
        let r = try #require(records.first)
        #expect(r.kind == "refund")
        #expect(r.note == "Reversed by the bank")
    }

    @Test func aSingaporeBankUsesSGD() throws {
        let records = EmailParsers.parse(message(
            "ibanking.alert@dbs.com", "Transaction alert",
            "Purchase of $22.10 at NTUC FAIRPRICE ORCHARD with card ending 5678."))
        let r = try #require(records.first)
        #expect(r.currency == "SGD")
    }

    @Test func aBankNewsletterProducesNothing() {
        let records = EmailParsers.parse(message(
            "marketing@nab.com.au", "Earn more on your savings",
            "Rates up to 4.50% p.a. Terms and conditions apply."))
        #expect(records.isEmpty)
    }

    @Test func theBankIsRecognisedAsAKnownSender() {
        #expect(EmailParsers.knowsSender("alerts@nab.com.au"))
        #expect(EmailParsers.knowsSender("ibanking.alert@dbs.com"))
        #expect(!EmailParsers.knowsSender("someone@gmail.com"))
    }
}
