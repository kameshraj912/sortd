import Testing
@testable import Spend

/// The setup screens must not promise more privacy than the app gives.
///
/// What is true: purchases, cards and email content stay on the iPhone. Usage
/// counts and crash reports (never amounts, shops, card digits, notes or
/// email) are sent unless "Share usage data" is off in Settings › Privacy &
/// Security › Privacy. So no setup line may say that everything stays, or that
/// nothing leaves, or that there is no server.
@MainActor
struct SetupPrivacyCopyTests {

    /// Phrases that claim nothing at all leaves the phone.
    private static let overclaims = [
        "nothing leaves",
        "never a server",
        "no server",
        "everything stays",
        "keeping everything",
        "stays on your iphone",
        "private by design",
    ]

    @Test func noSetupLineClaimsNothingLeavesThePhone() {
        for line in SetupCopy.privacyLines {
            let lower = line.lowercased()
            for claim in Self.overclaims {
                #expect(!lower.contains(claim), "\"\(line)\" still says \"\(claim)\"")
            }
        }
    }

    @Test func noSetupLineSaysEverythingStaysOnThePhone() {
        for line in SetupCopy.privacyLines {
            #expect(!line.lowercased().contains("everything"), "\"\(line)\" claims everything stays")
        }
    }

    @Test func thePlanAndBuildingLinesSayThePurchasesStay() {
        #expect(SetupCopy.planPrivacy.lowercased().contains("purchases"))
        #expect(SetupCopy.buildingPrivacy.lowercased().contains("purchases"))
        #expect(SetupCopy.welcomePrivacy.detail.lowercased().contains("purchases"))
    }

    /// Gmail really is read on the phone: that claim stays.
    @Test func theGmailLinesStillSayEmailIsReadOnTheIPhone() {
        #expect(SetupCopy.gmailOnDevice.contains("iPhone"))
        #expect(SetupCopy.gmailOnDevice.lowercased().contains("read"))
        #if !SORTD_ICLOUD
        #expect(SetupCopy.emailLine.contains("iPhone"))
        #expect(SetupCopy.emailLine.lowercased().contains("read"))
        #endif
    }

    /// Short and plain: one line on a phone screen, two at most.
    @Test func everyPrivacyLineIsShort() {
        for line in SetupCopy.privacyLines {
            #expect(line.count <= 80, "\"\(line)\" is \(line.count) characters")
        }
    }
}
