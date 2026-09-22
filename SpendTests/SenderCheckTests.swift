import Foundation
import Testing
@testable import Spend

/// A fake receipt "from" a bank or Apple must not be counted.
struct SenderCheckTests {
    private func msg(_ from: String, auth: Set<String>? = nil) -> EmailParsers.Message {
        var m = EmailParsers.Message(id: "m1", from: from, subject: "Receipt", body: "Total $10.00", date: .now)
        m.authenticatedDomains = auth
        return m
    }

    @Test func readsTheDomainFromTheAddressNotTheName() {
        #expect(EmailParsers.senderDomain("Apple <no_reply@email.apple.com>") == "email.apple.com")
        #expect(EmailParsers.senderDomain("no_reply@email.apple.com") == "email.apple.com")
        #expect(EmailParsers.senderDomain("apple.com <scam@evil.io>") == "evil.io")
        #expect(EmailParsers.senderDomain("no address here") == nil)
    }

    @Test func lookAlikeDomainsDontCount() {
        #expect(EmailParsers.isDomain("apple.com", within: "apple.com"))
        #expect(EmailParsers.isDomain("email.apple.com", within: "apple.com"))
        #expect(!EmailParsers.isDomain("notapple.com", within: "apple.com"))
        #expect(!EmailParsers.isDomain("apple.com.evil.io", within: "apple.com"))
        #expect(!EmailParsers.knowsSender("Apple <receipts@notapple.com>"))
        #expect(!EmailParsers.knowsSender("apple.com <scam@evil.io>"))
        #expect(EmailParsers.knowsSender("Apple <no_reply@email.apple.com>"))
    }

    @Test func banksAreMatchedOnTheRealDomain() {
        #expect(BankAlerts.bank(for: "DBS <alerts@dbs.com>")?.name == "DBS")
        #expect(BankAlerts.bank(for: "DBS <alerts@dbs.com.phish.io>") == nil)
        #expect(BankAlerts.bank(for: "dbs.com <alerts@phish.io>") == nil)
    }

    @Test func aFailedMailServerCheckIsRejected() {
        // Gmail proved it came from Apple.
        #expect(EmailParsers.isFrom(msg("Apple <no_reply@email.apple.com>", auth: ["email.apple.com"]), "apple.com"))
        // Claims Apple, but Gmail only proved some other domain sent it.
        #expect(!EmailParsers.isFrom(msg("Apple <no_reply@email.apple.com>", auth: ["evil.io"]), "apple.com"))
        #expect(!EmailParsers.isFrom(msg("Apple <no_reply@email.apple.com>", auth: []), "apple.com"))
        #expect(EmailParsers.parse(msg("DBS <alerts@dbs.com>", auth: [])).isEmpty)
        // No report from the source (tests, imports): the domain check alone.
        #expect(EmailParsers.isFrom(msg("Apple <no_reply@email.apple.com>"), "apple.com"))
    }

    @Test func readsGmailAuthenticationResults() {
        let header = "mx.google.com; dkim=pass header.i=@email.apple.com header.s=a header.b=x; spf=pass (google.com: domain of x) smtp.mailfrom=x@bounce.apple.com; dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=apple.com"
        #expect(GmailSync.authenticatedDomains(header) == ["email.apple.com", "apple.com"])
        let failed = "mx.google.com; dkim=fail header.i=@apple.com; dmarc=fail header.from=apple.com"
        #expect(GmailSync.authenticatedDomains(failed).isEmpty)
    }

    @Test func csvCellsCantRunAsFormulas() {
        #expect(CSVExport.escape("=HYPERLINK(\"http://x\")") == "\"'=HYPERLINK(\"\"http://x\"\")\"")
        #expect(CSVExport.escape("+61 shop") == "'+61 shop")
        #expect(CSVExport.escape("-5") == "'-5")
        #expect(CSVExport.escape("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSVExport.escape("Woolworths") == "Woolworths")
        #expect(CSVExport.escape("Coffee, cake") == "\"Coffee, cake\"")
    }
}
