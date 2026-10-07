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
}
