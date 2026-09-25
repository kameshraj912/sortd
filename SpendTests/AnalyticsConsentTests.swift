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
        func setOptedOut(_ out: Bool) { optOutCalls.append(out) }
    }

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
