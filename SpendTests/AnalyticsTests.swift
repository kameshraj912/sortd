import Testing
import Foundation
@testable import Spend

// MARK: - The contract this file pins (swift-builder: match this exactly)
//
// `Spend/Services/Analytics.swift` is the one door to PostHog. Nothing else in the
// app calls the PostHog SDK directly; everything goes through this facade, which is
// given an injectable `Sink` so it can be tested without the real SDK.
//
//   @MainActor @Observable final class Analytics {
//       enum Event: String, CaseIterable {
//           case setupStarted = "setup_started"
//           case setupStepCompleted = "setup_step_completed"
//           case setupFinished = "setup_finished"
//           case activationFirstAutoPurchase = "activation_first_auto_purchase"
//           case purchaseAddedManually = "purchase_added_manually"
//           case purchaseDeleted = "purchase_deleted"
//           case purchaseUndone = "purchase_undone"
//           case gmailConnected = "gmail_connected"
//           case gmailSyncFinished = "gmail_sync_finished"
//           case applePayTapLogged = "apple_pay_tap_logged"
//           case tabOpened = "tab_opened"
//           case tipLeft = "tip_left"
//           case backupCompleted = "backup_completed"
//           case restoreCompleted = "restore_completed"
//           case analyticsOptedOut = "analytics_opted_out"
//       }
//
//       protocol Sink: AnyObject {
//           func capture(_ name: String, properties: [String: Any])
//           func identify(_ id: String)
//           func reset()
//           func screen(_ name: String)
//       }
//
//       enum AnalyticsValue { case string(String), int(Int), double(Double), bool(Bool) }
//
//       init(sink: Sink, defaults: UserDefaults)
//
//       /// Persisted at `defaults["analyticsEnabled"]`. Default true. Setting it to
//       /// false posts `.analyticsOptedOut` exactly once (the transition), then every
//       /// later `track`/`screen` call is a no-op until it is set back to true.
//       /// Setting it to false again while already false does nothing.
//       var isEnabled: Bool { get set }
//
//       /// Sends `event.rawValue` and only scalar properties to the sink, when enabled.
//       /// A privacy guard runs first (see below); it can drop properties but never
//       /// blocks the event itself.
//       func track(_ event: Event, _ properties: [String: AnalyticsValue] = [:])
//
//       func screen(_ name: String)
//
//       /// identify(distinctId(salt: accountSalt, provider:, subject:)); the salt
//       /// is one fixed app-wide constant (`Analytics.accountSalt`), so the id is
//       /// the same on every phone and after a reinstall (sub-spec 4).
//       /// Never sends the email or the raw subject.
//       func signedIn(provider: String, subject: String)
//
//       /// reset() on the sink.
//       func signedOut()
//
//       /// Pure: sha256Hex(salt + provider + subject), lowercase, 64 hex characters.
//       static func distinctId(salt: String, provider: String, subject: String) -> String
//
//       /// Privacy guard trail, for tests only: one entry ("event.key") per property
//       /// `track` dropped, in DEBUG builds. Never a crash; the event still sends.
//       private(set) var violations: [String]
//   }
//
// Privacy guard (runs inside `track`, before the sink is called):
//   - Any property key in `["amount","merchant","email","note","subject",
//     "currency_amount","aud"]` is dropped outright, whatever its value.
//   - Any *string* value matching money (`[A-Z]{0,3}\$?\s?\d+[.,]\d{2}`) or an email
//     (`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`) is dropped, even under a safe key.
//   - The event still sends with the remaining, safe properties.

@MainActor
final class SpySink: Analytics.Sink {
    private(set) var captured: [(name: String, properties: [String: Any])] = []
    private(set) var identified: [String] = []
    private(set) var resets = 0
    private(set) var screens: [String] = []

    func capture(_ name: String, properties: [String: Any]) { captured.append((name, properties)) }
    func identify(_ id: String) { identified.append(id) }
    func reset() { resets += 1 }
    func screen(_ name: String) { screens.append(name) }
}

@MainActor
struct AnalyticsTests {
    private func makeAnalytics(suite: String) -> (Analytics, SpySink, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let sink = SpySink()
        return (Analytics(sink: sink, defaults: defaults), sink, defaults)
    }

    // MARK: enabled by default / opt-out / opt-in

    @Test func enabledByDefault() {
        let (analytics, _, _) = makeAnalytics(suite: #function)
        #expect(analytics.isEnabled)
    }

    @Test func whenDisabledNothingReachesTheSinkExceptTheOneOptOutEvent() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.isEnabled = false
        #expect(sink.captured.count == 1)
        #expect(sink.captured.first?.name == Analytics.Event.analyticsOptedOut.rawValue)

        analytics.track(.tabOpened, ["tab": .string("home")])
        analytics.screen("Home")
        #expect(sink.captured.count == 1, "no further events reach the sink once disabled")
        #expect(sink.screens.isEmpty)
    }

    @Test func disablingAgainWhileAlreadyDisabledSendsNothingMore() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.isEnabled = false
        analytics.isEnabled = false
        #expect(sink.captured.count == 1, "opted_out only fires on the transition, once")
    }

    @Test func reenablingResumesTracking() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.isEnabled = false
        analytics.isEnabled = true
        analytics.track(.tabOpened, ["tab": .string("home")])
        #expect(sink.captured.count == 2)
        #expect(sink.captured.last?.name == Analytics.Event.tabOpened.rawValue)
    }

    @Test func enabledFlagPersistsAcrossTwoInstancesOnTheSameSuite() {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = Analytics(sink: SpySink(), defaults: defaults)
        first.isEnabled = false

        let second = Analytics(sink: SpySink(), defaults: defaults)
        #expect(second.isEnabled == false)
    }

    // MARK: track basics

    @Test func trackSendsTheEventsRawNameAndOnlyScalarProperties() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.track(.purchaseAddedManually, ["step": .int(2), "ratio": .double(0.5), "ok": .bool(true), "kind": .string("card")])
        let sent = sink.captured.last
        #expect(sent?.name == "purchase_added_manually")
        #expect(sent?.properties["step"] as? Int == 2)
        #expect(sent?.properties["ratio"] as? Double == 0.5)
        #expect(sent?.properties["ok"] as? Bool == true)
        #expect(sent?.properties["kind"] as? String == "card")
    }

    // MARK: privacy guard

    @Test func denyListedKeysAreDroppedButTheEventStillSends() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        let deny = ["amount", "merchant", "email", "note", "subject", "currency_amount", "aud"]
        for key in deny {
            analytics.track(.purchaseAddedManually, [key: .string("harmless")])
        }
        #expect(sink.captured.count == deny.count, "every event still sends")
        for sent in sink.captured {
            #expect(sent.properties.isEmpty, "the deny-listed key never reaches the sink")
        }
        for key in deny {
            #expect(analytics.violations.contains(where: { $0.hasSuffix(".\(key)") }))
        }
    }

    @Test func aMoneyLookingStringValueIsDroppedEvenUnderASafeKey() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.track(.tipLeft, ["label": .string("A$12.34"), "tier": .string("gold")])
        let sent = sink.captured.last
        #expect(sent?.properties["label"] == nil)
        #expect(sent?.properties["tier"] as? String == "gold")
        #expect(analytics.violations.contains(where: { $0.hasSuffix(".label") }))
    }

    @Test func anEmailLookingStringValueIsDroppedEvenUnderASafeKey() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.track(.gmailConnected, ["contact": .string("raj@example.com"), "provider": .string("google")])
        let sent = sink.captured.last
        #expect(sent?.properties["contact"] == nil)
        #expect(sent?.properties["provider"] as? String == "google")
        #expect(analytics.violations.contains(where: { $0.hasSuffix(".contact") }))
    }

    @Test func safePropertiesPassThroughUntouched() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.track(.setupStepCompleted, ["step": .int(3), "skipped": .bool(false)])
        #expect(analytics.violations.isEmpty)
        let sent = sink.captured.last
        #expect(sent?.properties["step"] as? Int == 3)
        #expect(sent?.properties["skipped"] as? Bool == false)
    }

    // MARK: identity

    @Test func signedInIdentifiesWithASixtyFourHexCharacterId() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedIn(provider: "apple", subject: "001.abc.def")
        let id = try! #require(sink.identified.first)
        #expect(id.count == 64)
        #expect(id.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func signedInIdNeverContainsTheSubjectOrAnAtSign() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedIn(provider: "google", subject: "raj@example.com")
        let id = try! #require(sink.identified.first)
        #expect(!id.contains("raj"))
        #expect(!id.contains("@"))
        #expect(!id.contains("example"))
    }

    @Test func sameSubjectAndProviderGiveTheSameIdAcrossCalls() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedIn(provider: "apple", subject: "001.abc")
        analytics.signedIn(provider: "apple", subject: "001.abc")
        #expect(sink.identified.count == 2)
        #expect(sink.identified[0] == sink.identified[1])
    }

    @Test func differentProvidersGiveDifferentIds() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedIn(provider: "apple", subject: "same-subject")
        analytics.signedIn(provider: "google", subject: "same-subject")
        #expect(sink.identified[0] != sink.identified[1])
    }

    /// The salt is fixed and app-wide, so the id is the same on every phone
    /// and is exactly what `AccountStore` uses (sub-spec 4).
    @Test func signedInIdIsTheAccountStoreHashWithTheFixedAccountSalt() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedIn(provider: "apple", subject: "001.abc")
        let expected = AccountStore.hash(salt: Analytics.accountSalt, provider: .apple, subject: "001.abc")
        #expect(sink.identified.first == expected)
        #expect(Analytics.accountSalt.count >= 32)
    }

    @Test func signedOutCallsReset() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.signedOut()
        #expect(sink.resets == 1)
    }

    @Test func screenForwardsTheName() {
        let (analytics, sink, _) = makeAnalytics(suite: #function)
        analytics.screen("Home")
        #expect(sink.screens == ["Home"])
    }

    // MARK: consent survives Delete All

    @Test func disabledSurvivesADefaultsWipeWhenTheCallerRestoresIt() {
        let suite = #function
        let (analytics, sink, defaults) = makeAnalytics(suite: suite)
        analytics.isEnabled = false
        #expect(defaults.object(forKey: "analyticsConsentChangedAt") is Date)
        // Delete All: the app's defaults go, then signedOut() resets the sink.
        analytics.preserveConsent {
            defaults.removePersistentDomain(forName: suite)
            analytics.signedOut()
        }
        #expect(analytics.isEnabled == false)
        #expect(defaults.object(forKey: "analyticsEnabled") as? Bool == false)
        #expect(defaults.object(forKey: "analyticsConsentChangedAt") is Date)
        #expect(sink.resets == 1)
        analytics.track(.tabOpened, ["tab": .string("home")])
        #expect(sink.captured.count == 1, "still off: only the original opt-out was ever sent")
        let relaunch = Analytics(sink: SpySink(), defaults: defaults)
        #expect(relaunch.isEnabled == false)
    }

    // MARK: trackOnce (activation)

    /// `isDemo` is injected: a simulator that once ran with SPEND_DEMO=1 has
    /// `demoActive` set in the shared app container, and the test host reads it.
    private func makeNonDemoAnalytics(suite: String) -> (Analytics, SpySink) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let sink = SpySink()
        return (Analytics(sink: sink, defaults: defaults, isDemo: { false }), sink)
    }

    @Test func trackOnceFiresOncePerInstall() {
        let (analytics, sink) = makeNonDemoAnalytics(suite: #function)
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("email")])
        #expect(sink.captured.count == 1)
        #expect(sink.captured.first?.properties["source"] as? String == "tap")
        #expect(sink.captured.first?.properties["hours_bucket"] as? String == "under_1h")
    }

    @Test func trackOnceDoesNotConsumeTheFlagWhileDisabled() {
        let (analytics, sink) = makeNonDemoAnalytics(suite: #function)
        analytics.isEnabled = false
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
        #expect(sink.captured.count == 1, "only the opt-out")
        analytics.isEnabled = true
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
        #expect(sink.captured.last?.name == "activation_first_auto_purchase")
    }

    @Test func trackOnceSkipsSampleData() {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let sink = SpySink()
        var demo = true
        let analytics = Analytics(sink: sink, defaults: defaults, isDemo: { demo })
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
        #expect(sink.captured.isEmpty)
        demo = false
        analytics.trackOnce(.activationFirstAutoPurchase, ["source": .string("tap")])
        #expect(sink.captured.count == 1, "the flag was not consumed by the demo run")
    }

    @Test func aTestTapNeverCountsAsActivation() {
        #expect(!LogPurchaseIntent.countsAsActivation(added: true, merchant: LogPurchaseIntent.legacyTestMerchant))
        #expect(!LogPurchaseIntent.countsAsActivation(added: false, merchant: "Woolworths"))
        #expect(LogPurchaseIntent.countsAsActivation(added: true, merchant: "Woolworths"))
    }

    // MARK: event names

    @Test func everyEventRawValueIsSnakeCaseAscii() {
        let pattern = try! Regex("^[a-z][a-z0-9_]*$")
        for event in Analytics.Event.allCases {
            #expect(event.rawValue.wholeMatch(of: pattern) != nil, "\(event.rawValue) is not snake_case ASCII")
        }
    }
}
