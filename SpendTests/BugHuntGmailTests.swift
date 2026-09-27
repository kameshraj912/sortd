import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Spend

/// Bug hunt 26 Sep 2026, area gmail-security. Each known-bug case fails
/// today and documents one finding; the untagged cases are controls that
/// show the neighbouring path works.
@MainActor
struct BugHuntGmailTests {

    // MARK: - App Lock

    private func fresh() -> AppLock {
        // `AppLock()` reads the switch from UserDefaults; start unlocked,
        // and clear any stored "require after" choice so the default
        // (immediately) applies, regardless of what a real device has saved.
        UserDefaults.standard.set(false, forKey: AppLock.enabledKey)
        UserDefaults.standard.removeObject(forKey: AppLock.requireAfterKey)
        return AppLock()
    }

    /// App Lock never locks again after the first unlock: coming back from
    /// the background goes background → inactive → active, and the
    /// `.inactive` step sets `lastActive = now`, so `.active` sees no time away.
    @Test
    func appLockLocksAgainAfterTenMinutesAway() {
        let lock = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Leaving the app: active → inactive → background.
        lock.sceneChanged(to: .inactive, enabled: true, onboarded: true, now: t0)
        lock.sceneChanged(to: .background, enabled: true, onboarded: true, now: t0)
        // Ten minutes later, coming back: background → inactive → active.
        let back = t0.addingTimeInterval(600)
        lock.sceneChanged(to: .inactive, enabled: true, onboarded: true, now: back)
        lock.sceneChanged(to: .active, enabled: true, onboarded: true, now: back)
        #expect(lock.isLocked, "ten minutes away with App Lock on must lock")
    }

    /// Control: without the `.inactive` step the same trip does lock, which
    /// pins the cause to that step and not to `shouldLock`.
    @Test func appLockLocksWhenActiveFollowsBackgroundDirectly() {
        let lock = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        lock.sceneChanged(to: .background, enabled: true, onboarded: true, now: t0)
        lock.sceneChanged(to: .active, enabled: true, onboarded: true, now: t0.addingTimeInterval(600))
        #expect(lock.isLocked)
    }

    // MARK: - Sender check

    private func gmailMessage(from: String, headers extra: [GmailSync.MessageResponse.Header] = []) -> EmailParsers.Message? {
        let body = Data("You just spent $58.30 at WOOLWORTHS on your card ending 1234.".utf8).base64URL
        let payload = GmailSync.MessageResponse.Part(
            mimeType: "text/plain",
            headers: [.init(name: "From", value: from), .init(name: "Subject", value: "Transaction alert")] + extra,
            body: .init(data: body), parts: nil)
        return GmailSync.message(from: .init(id: "18f0a1b2c3d4e5f6", internalDate: "1800000000000", payload: payload))
    }

    /// A Gmail message with no `Authentication-Results: mx.google.com`
    /// header gets `authenticatedDomains == nil`, and nil means "trust the
    /// From address alone": a bank alert "from" dbs.com is accepted with no
    /// DKIM or DMARC proof. For mail read from Gmail, no report should mean
    /// no proof (an empty set), not a pass.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "hunt-gmail-2", "GmailSync.message(from:): no Authentication-Results header → sender trusted on From alone"))
    func aBankAlertWithNoGmailAuthenticationResultIsNotTrusted() throws {
        let msg = try #require(gmailMessage(from: "DBS <alerts@dbs.com>"))
        #expect(msg.authenticatedDomains == [], "Gmail gave no proof, so the proven set should be empty")
        #expect(!EmailParsers.isFrom(msg, "dbs.com"))
    }

    /// Control: the same message with Gmail's own failed check is rejected,
    /// and with a pass it is accepted.
    @Test func gmailsOwnAuthenticationResultDecides() throws {
        let failed = try #require(gmailMessage(from: "DBS <alerts@dbs.com>", headers: [
            .init(name: "Authentication-Results", value: "mx.google.com; dkim=fail header.i=@dbs.com; dmarc=fail header.from=dbs.com"),
        ]))
        #expect(failed.authenticatedDomains == [])
        #expect(!EmailParsers.isFrom(failed, "dbs.com"))

        let passed = try #require(gmailMessage(from: "DBS <alerts@dbs.com>", headers: [
            .init(name: "Authentication-Results", value: "mx.google.com; dkim=pass header.i=@dbs.com; dmarc=pass header.from=dbs.com"),
        ]))
        #expect(passed.authenticatedDomains == ["dbs.com"])
        #expect(EmailParsers.isFrom(passed, "dbs.com"))
    }
}
