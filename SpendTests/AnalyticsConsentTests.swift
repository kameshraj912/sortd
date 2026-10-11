import Testing
import Foundation
@testable import Spend

/// Analytics consent before tracking in the EU, EEA, UK and Switzerland.
///
/// With no stored choice, the "Share usage data" switch starts off when the
/// iPhone's region is in the EU/EEA, the UK or Switzerland (or unknown), and
/// on elsewhere. The default is never written to disk: only flipping the
/// switch stores a choice, so someone who moves region and never chose still
/// gets the new region's default. Crash reports share the switch.
@MainActor
struct AnalyticsConsentTests {

    /// Records the SDK opt-out calls too, which `SpySink` leaves out.
    final class ConsentSpySink: Analytics.Sink {
        private(set) var captured: [String] = []
        private(set) var screens: [String] = []
        private(set) var optOutCalls: [Bool] = []
        func capture(_ name: String, properties: [String: Any]) { captured.append(name) }
        func identify(_ id: String) {}
        func reset() {}
        func screen(_ name: String) { screens.append(name) }
        func setOptedOut(_ out: Bool, identity: String?) { optOutCalls.append(out) }
    }

    /// Stands in for the PostHog SDK: records set-up and person calls.
    final class FakePostHogClient: PostHogClient {
        private(set) var setupCount = 0
        private(set) var identified: [String] = []
        private(set) var resets = 0
        private(set) var optIns = 0
        private(set) var optOuts = 0
        private(set) var captured: [String] = []
        private(set) var unregistered: [String] = []
        var distinctId = "0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"

        func setup(apiKey: String, host: URL) { setupCount += 1 }
        func capture(_ name: String, properties: [String: Any]) { captured.append(name) }
        func identify(_ id: String) { identified.append(id); distinctId = id }
        func reset() { resets += 1; distinctId = "0190a1b2-0000-7e5f-8a9b-0c1d2e3f4a5b" }
        func screen(_ name: String) {}
        func isFeatureEnabled(_ key: String) -> Bool { true }
        func optIn() { optIns += 1 }
        func optOut() { optOuts += 1 }
        func unregister(_ key: String) { unregistered.append(key) }
    }

    private let host = URL(string: "https://eu.i.posthog.com")!
    private let hashA = String(repeating: "a1", count: 32)
    private let hashB = String(repeating: "b2", count: 32)

    private func fresh(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: defaultConsent(regionCode:)

    /// EU 27, the rest of the EEA, the UK and Switzerland.
    static let optInRegions = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
        "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        "IS", "LI", "NO",
        "GB", "CH",
        // Crown dependencies and Gibraltar follow UK-style rules.
        "GG", "JE", "IM", "GI",
    ]

    @Test(arguments: optInRegions)
    func offByDefaultInTheEEAUKAndSwitzerland(_ region: String) {
        #expect(Analytics.defaultConsent(regionCode: region) == false)
    }

    @Test(arguments: ["AU", "SG", "US", "NZ", "JP", "IN", "MY", "CA"])
    func onByDefaultElsewhere(_ region: String) {
        #expect(Analytics.defaultConsent(regionCode: region) == true)
    }

    /// EU regions outside mainland Europe follow the EU rules too.
    @Test(arguments: ["GP", "MQ", "GF", "RE", "YT", "MF", "AX", "IC", "EA"])
    func offInEURegionsOutsideMainlandEurope(_ region: String) {
        #expect(Analytics.defaultConsent(regionCode: region) == false)
    }

    @Test func offWhenTheRegionIsUnknown() {
        #expect(Analytics.defaultConsent(regionCode: nil) == false)
        #expect(Analytics.defaultConsent(regionCode: "") == false)
        // "150" is Europe as a whole, "001" the world: not a country.
        #expect(Analytics.defaultConsent(regionCode: "150") == false)
        #expect(Analytics.defaultConsent(regionCode: "001") == false)
    }

    @Test func theRegionCodeIsReadInAnyCase() {
        #expect(Analytics.defaultConsent(regionCode: "de") == false)
        #expect(Analytics.defaultConsent(regionCode: "gb") == false)
        #expect(Analytics.defaultConsent(regionCode: "au") == true)
    }

    // MARK: A fresh install

    @Test func aFreshInstallInGermanyStartsOffAndSendsNothing() {
        let sink = ConsentSpySink()
        let analytics = Analytics(sink: sink, defaults: fresh(#function), isDemo: { false }, regionCode: "DE")
        #expect(analytics.isEnabled == false)

        analytics.track(.setupStarted)
        analytics.screen("Welcome")
        analytics.trackOnce(.activationFirstAutoPurchase)
        #expect(sink.captured.isEmpty, "not even the opt-out event: the user never opted in")
        #expect(sink.screens.isEmpty)
    }

    @Test func aFreshInstallInTheUKStartsOff() {
        let analytics = Analytics(sink: ConsentSpySink(), defaults: fresh(#function), regionCode: "GB")
        #expect(analytics.isEnabled == false)
    }

    @Test func aFreshInstallInAustraliaStartsOn() {
        let sink = ConsentSpySink()
        let analytics = Analytics(sink: sink, defaults: fresh(#function), regionCode: "AU")
        #expect(analytics.isEnabled == true)
        analytics.track(.setupStarted)
        #expect(sink.captured == [Analytics.Event.setupStarted.rawValue])
    }

    /// Crash reports share the switch: with the default off, Sentry must not start.
    @Test func crashReportsStayOffWhenTheDefaultIsOff() {
        let analytics = Analytics(sink: ConsentSpySink(), defaults: fresh(#function), regionCode: "FR")
        #expect(CrashReporting.enabled(isDebug: false, dsn: "https://x@o.ingest.sentry.io/1",
                                       consent: analytics.isEnabled) == false)
    }

    // MARK: Nothing new is stored

    @Test func theDefaultIsNotWrittenToDisk() {
        let defaults = fresh(#function)
        _ = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        _ = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "AU")
        #expect(defaults.object(forKey: Analytics.enabledKey) == nil)
        #expect(defaults.object(forKey: Analytics.consentChangedAtKey) == nil)
    }

    @Test func movingRegionWithoutChoosingUsesTheNewRegionsDefault() {
        let defaults = fresh(#function)
        let inGermany = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        #expect(inGermany.isEnabled == false)
        let inAustralia = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "AU")
        #expect(inAustralia.isEnabled == true)
        let backInGermany = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        #expect(backInGermany.isEnabled == false)
    }

    // MARK: The switch is the way to change it

    @Test func turningItOnInGermanyIsStoredAndBeatsTheRegion() {
        let defaults = fresh(#function)
        let sink = ConsentSpySink()
        let analytics = Analytics(sink: sink, defaults: defaults, regionCode: "DE")
        analytics.isEnabled = true
        #expect(defaults.object(forKey: Analytics.enabledKey) as? Bool == true)
        #expect(defaults.object(forKey: Analytics.consentChangedAtKey) is Date)
        #expect(sink.optOutCalls == [false])
        #expect(sink.captured.isEmpty, "turning it on sends no opt-out event")

        analytics.track(.tabOpened, ["tab": .string("home")])
        #expect(sink.captured == [Analytics.Event.tabOpened.rawValue])

        let relaunch = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        #expect(relaunch.isEnabled == true)
    }

    @Test func turningItOffInAustraliaBeatsTheRegion() {
        let defaults = fresh(#function)
        let analytics = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "AU")
        analytics.isEnabled = false
        let relaunch = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "AU")
        #expect(relaunch.isEnabled == false)
    }

    /// Older builds wrote `true` on Delete All without anyone choosing (no
    /// change date). That is not a choice: the region default applies.
    @Test func aStoredTrueWithoutAChangeDateIsNotAChoice() {
        let defaults = fresh(#function)
        defaults.set(true, forKey: Analytics.enabledKey)
        let analytics = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        #expect(analytics.isEnabled == false)
        #expect(Analytics.storedChoice(in: defaults) == nil)
    }

    @Test func aStoredChoiceWithAChangeDateIsKept() {
        let defaults = fresh(#function)
        defaults.set(true, forKey: Analytics.enabledKey)
        defaults.set(Date.now, forKey: Analytics.consentChangedAtKey)
        let analytics = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        #expect(analytics.isEnabled == true)
    }

    // MARK: PostHog set-up

    @Test func postHogIsNotSetUpWhileSharingIsOff() {
        let client = FakePostHogClient()
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        sink.capture("setup_started", properties: [:])
        sink.screen("Welcome")
        sink.identify(hashA)
        sink.reset()
        sink.setOptedOut(true, identity: nil)
        #expect(client.setupCount == 0)
        #expect(client.captured.isEmpty)
        #expect(client.identified.isEmpty)
        #expect(client.resets == 0)
        #expect(sink.isFeatureEnabled("any") == false)
    }

    @Test func turningSharingOnSetsPostHogUpExactlyOnce() {
        let client = FakePostHogClient()
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        sink.setOptedOut(false, identity: nil)
        #expect(client.setupCount == 1)
        #expect(client.optIns == 1)
        sink.setOptedOut(true, identity: nil)
        sink.setOptedOut(false, identity: nil)
        #expect(client.setupCount == 1)
        #expect(client.optOuts == 1)
        sink.capture("tab_opened", properties: [:])
        #expect(client.captured == ["tab_opened"])
    }

    @Test func postHogIsSetUpAtLaunchWhenSharingIsOn() {
        let client = FakePostHogClient()
        _ = PostHogSink(apiKey: "phc_test", host: host, enabled: true, identity: nil, client: client)
        #expect(client.setupCount == 1)
    }

    /// PostHog keeps super properties on disk: last session's `screen` is
    /// dropped at set-up, before any screen registers or a background
    /// intent run sends an event.
    @Test func setUpDropsTheScreenKeptFromLastSession() {
        let client = FakePostHogClient()
        _ = PostHogSink(apiKey: "phc_test", host: host, enabled: true, identity: nil, client: client)
        #expect(client.unregistered == ["screen"])
    }

    /// Signed in while sharing was off: turning it on identifies as the hash.
    @Test func turningSharingOnIdentifiesASignedInPerson() {
        let client = FakePostHogClient()
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        sink.setOptedOut(false, identity: hashA)
        #expect(client.identified == [hashA])
        #expect(client.resets == 0)
    }

    /// Signed in as someone else since the SDK last saw it: identify again.
    @Test func turningSharingOnReidentifiesWhenTheHashChanged() {
        let client = FakePostHogClient()
        client.distinctId = hashA
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        sink.setOptedOut(false, identity: hashB)
        #expect(client.identified == [hashB])
    }

    @Test func turningSharingOnLeavesTheRightPersonAlone() {
        let client = FakePostHogClient()
        client.distinctId = hashA
        _ = PostHogSink(apiKey: "phc_test", host: host, enabled: true, identity: hashA, client: client)
        #expect(client.identified.isEmpty)
        #expect(client.resets == 0)
    }

    /// Signed out or Delete All while sharing was off: the SDK still carries
    /// the old hash, so it is reset and the deleted person doesn't come back.
    @Test func turningSharingOnResetsAPersonWhoSignedOutMeanwhile() {
        let client = FakePostHogClient()
        client.distinctId = hashA
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        sink.setOptedOut(false, identity: nil)
        #expect(client.resets == 1)
        #expect(client.identified.isEmpty)
    }

    @Test func anAnonymousPersonIsNotReset() {
        let client = FakePostHogClient()
        _ = PostHogSink(apiKey: "phc_test", host: host, enabled: true, identity: nil, client: client)
        #expect(client.resets == 0)
        #expect(PostHogSink.looksIdentified(hashA))
        #expect(!PostHogSink.looksIdentified(client.distinctId))
    }

    /// The facade hands the kept hash to the sink when sharing turns on.
    @Test func theFacadePassesTheSignedInHashWhenSharingTurnsOn() {
        let client = FakePostHogClient()
        let sink = PostHogSink(apiKey: "phc_test", host: host, enabled: false, identity: nil, client: client)
        let analytics = Analytics(sink: sink, defaults: fresh(#function), regionCode: "DE")
        analytics.signedIn(hash: hashA)
        #expect(client.identified.isEmpty, "sharing is off: nothing reaches PostHog")
        analytics.isEnabled = true
        #expect(client.setupCount == 1)
        #expect(client.identified == [hashA])
    }

    // MARK: Delete All Data

    /// Someone who never chose must not come out of Delete All with a
    /// stored choice they never made.
    @Test func deleteAllKeepsNoChoiceWhenNoneWasMade() {
        let suite = #function
        let defaults = fresh(suite)
        let sink = ConsentSpySink()
        let analytics = Analytics(sink: sink, defaults: defaults, regionCode: "DE")
        analytics.preserveConsent {
            defaults.removePersistentDomain(forName: suite)
            analytics.signedOut()
        }
        #expect(defaults.object(forKey: Analytics.enabledKey) == nil)
        #expect(analytics.isEnabled == false)
        #expect(sink.optOutCalls.last == true, "PostHog's own opt-out is put back after reset()")
        analytics.track(.setupStarted)
        #expect(sink.captured.isEmpty)
    }

    @Test func deleteAllStillKeepsAChoiceThatWasMade() {
        let suite = #function
        let defaults = fresh(suite)
        let analytics = Analytics(sink: ConsentSpySink(), defaults: defaults, regionCode: "DE")
        analytics.isEnabled = true
        analytics.preserveConsent {
            defaults.removePersistentDomain(forName: suite)
        }
        #expect(defaults.object(forKey: Analytics.enabledKey) as? Bool == true)
        #expect(analytics.isEnabled == true)
    }
}
