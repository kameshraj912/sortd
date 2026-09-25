import Foundation
import CryptoKit
import Observation
import PostHog
import os

/// The one door to PostHog. Nothing else in the app calls the SDK; every
/// screen goes through `Analytics.shared`, which sends named events with
/// scalar properties to a `Sink`. Tests give it a fake sink.
///
/// What is never sent: amounts, merchants, emails, notes, card digits or
/// anything read from Gmail. A privacy guard drops a property whose key is
/// on the deny list or whose value looks like money or an email; the event
/// still goes with what is left.
///
/// Identity: before sign-in PostHog's own anonymous id is the per-install id.
/// `signedIn` identifies as sha256(accountSalt + provider + subject), where
/// `accountSalt` is one fixed string compiled into the app, so the same
/// person is the same PostHog person on every phone and after a reinstall,
/// and the id never carries the email or the raw subject. `signedOut` resets.
///
/// Consent: until the user flips the switch (Settings › Privacy), the
/// default depends on the iPhone's region: off in the EU/EEA, the UK and
/// Switzerland (and when the region is unknown), where the law wants opt-in,
/// and on elsewhere. The default is never stored, so only a real choice is.
/// Off at launch means PostHog is not even set up and Sentry does not start.
/// Turning it off sends `analytics_opted_out` once, then nothing.
@MainActor @Observable
final class Analytics {
    enum Event: String, CaseIterable {
        case setupStarted = "setup_started"
        case setupStepViewed = "setup_step_viewed"
        case setupStepCompleted = "setup_step_completed"
        case setupFinished = "setup_finished"
        case activationFirstAutoPurchase = "activation_first_auto_purchase"
        case purchaseAddedManually = "purchase_added_manually"
        case purchaseDeleted = "purchase_deleted"
        case purchaseUndone = "purchase_undone"
        case gmailConnected = "gmail_connected"
        case gmailSyncFinished = "gmail_sync_finished"
        case applePayTapLogged = "apple_pay_tap_logged"
        case tabOpened = "tab_opened"
        case tipLeft = "tip_left"
        case tipShown = "tip_shown"
        case tipUsed = "tip_used"
        /// The app intro (docs/specs/2026-09-25-app-intro.md): once per
        /// showing, and once per showing when it ends.
        case introShown = "intro_shown"
        case introFinished = "intro_finished"
        case backupCompleted = "backup_completed"
        case restoreCompleted = "restore_completed"
        case analyticsOptedOut = "analytics_opted_out"
        /// Sign-in (sub-spec 4): `provider` is apple or google, never the email.
        case signedIn = "signed_in"
        case signedOut = "signed_out"
    }

    /// Where events go. `PostHogSink` in the app, `NoopSink` with no key,
    /// a spy in tests.
    protocol Sink: AnyObject {
        func capture(_ name: String, properties: [String: Any])
        func identify(_ id: String)
        func reset()
        func screen(_ name: String)
        /// PostHog feature flag. Unknown, offline or a sink that has no
        /// flags: false, so the default screen shows. Optional: a sink
        /// without flags (a spy in tests) leaves it out.
        func isFeatureEnabled(_ key: String) -> Bool
        /// The SDK's own opt-out switch (PostHog keeps it in its storage,
        /// which `reset()` wipes). Optional; a spy leaves it out.
        func setOptedOut(_ out: Bool)
    }

    /// Only scalars can be a property: no arrays, no dictionaries, nothing
    /// that could smuggle a purchase through.
    enum AnalyticsValue {
        case string(String), int(Int), double(Double), bool(Bool)

        var any: Any {
            switch self {
            case .string(let s): s
            case .int(let i): i
            case .double(let d): d
            case .bool(let b): b
            }
        }
    }

    static let enabledKey = "analyticsEnabled"
    /// When the switch was last flipped: the consent record, kept on the phone.
    static let consentChangedAtKey = "analyticsConsentChangedAt"
    /// The identified hash, kept so a crash sent on the next launch still
    /// carries it. Cleared on `signedOut`.
    static let identityHashKey = "analyticsIdentityHash"
    /// The salt in the signed-in id. Fixed and app-wide on purpose: a
    /// per-phone salt would make one person two PostHog persons on two
    /// phones. Not a secret; it only stops a plain lookup of a known Apple
    /// or Google subject. `AccountStore.hash` uses the same string.
    nonisolated static let accountSalt = "ecb29d9facc0de3bd8ec45788386868cd4f679dbc3c20e92e2ea7b58b40b3fb6"
    /// Prefix for `trackOnce`: "<prefix>.<event>" is set once per install.
    static let activatedKey = "analyticsActivated"
    /// When this install first ran, for the activation hours bucket.
    static let installedAtKey = "analyticsInstalledAt"

    /// Property keys that never leave the phone, whatever the value.
    static let deniedKeys: Set<String> = ["amount", "merchant", "email", "note", "subject", "currency_amount", "aud"]
    private static let moneyPattern = #"[A-Z]{0,3}\$?\s?\d+[.,]\d{2}"#
    private static let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#

    // MARK: - App instance

    /// Real PostHog when the build has a key, otherwise nothing leaves the
    /// phone. Made on first use; `start()` makes that happen at launch.
    static let shared: Analytics = {
        let key = (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let region = Locale.current.region?.identifier
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultConsent(regionCode: region)
        // A host with no scheme is a broken xcconfig line ("//" is a comment
        // there): fall back to the EU host rather than send to nowhere.
        let hostText = host.contains("://") ? host : PostHogSink.defaultHost
        guard !key.isEmpty, let hostURL = URL(string: hostText) else {
            log.notice("analytics off: no key (POSTHOG_API_KEY is empty), nothing is sent")
            return Analytics(sink: NoopSink(), defaults: .standard, regionCode: region)
        }
        let sink = PostHogSink(apiKey: key, host: hostURL, enabled: enabled)
        log.info("analytics on: PostHog at \(hostURL.host() ?? host, privacy: .public), sharing \(enabled ? "on" : "off", privacy: .public)")
        return Analytics(sink: sink, defaults: .standard, regionCode: region)
    }()

    /// Call once at launch so the SDK starts (and logs) before any event.
    static func start() { _ = shared }

    /// A PostHog feature flag, for A/B tests between shipped screens only
    /// (never to switch on hidden features: guideline 2.3.1, see Features).
    /// Unknown, offline or no key: false.
    static func flag(_ key: String) -> Bool { shared.sink.isFeatureEnabled(key) }

    // MARK: - Instance

    private let sink: Sink
    private let defaults: UserDefaults
    /// Sample data is loaded: `trackOnce` (activation) must not count it.
    private let isDemo: @MainActor () -> Bool
    /// Mirrors the persisted flag so SwiftUI sees the switch change.
    private var enabled: Bool

    /// Privacy guard trail, for tests: "event.key" per property dropped.
    private(set) var violations: [String] = []

    /// The identified id (the salted hash) while signed in, else nil. Read
    /// by `CrashReporting` from Sentry's own thread, so it sits behind a
    /// lock rather than on the main actor. Persisted at `identityHashKey`:
    /// Sentry sends a crash on the next launch, after this object is new.
    nonisolated var identityHash: String? { identityBox.withLock { $0 } }
    private nonisolated let identityBox = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(sink: Sink, defaults: UserDefaults, isDemo: @escaping @MainActor () -> Bool = { DemoData.isActive },
         regionCode: String? = Locale.current.region?.identifier) {
        self.sink = sink
        self.defaults = defaults
        self.isDemo = isDemo
        self.enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultConsent(regionCode: regionCode)
        if let kept = defaults.string(forKey: Self.identityHashKey), kept.count == 64 {
            identityBox.withLock { $0 = kept }
        }
        // First launch only; never overwritten (preserveConsent keeps it
        // across Delete All).
        if defaults.object(forKey: Self.installedAtKey) == nil {
            defaults.set(Date.now, forKey: Self.installedAtKey)
        }
    }

    /// Persisted at `analyticsEnabled` once the user flips it; until then
    /// `defaultConsent(regionCode:)`. Off sends the one
    /// opt-out event on the transition, then `track` and `screen` do nothing
    /// until it is on again. Off while already off does nothing.
    var isEnabled: Bool {
        get { enabled }
        set {
            guard newValue != enabled else { return }
            defaults.set(Date.now, forKey: Self.consentChangedAtKey)
            if newValue {
                enabled = true
                defaults.set(true, forKey: Self.enabledKey)
                sink.setOptedOut(false)
            } else {
                // Sent while still enabled, so the sink takes it.
                sink.capture(Event.analyticsOptedOut.rawValue, properties: [:])
                enabled = false
                defaults.set(false, forKey: Self.enabledKey)
                sink.setOptedOut(true)
            }
            // One switch for both: crash reports follow analytics consent.
            CrashReporting.consentChanged(to: newValue, analytics: self)
        }
    }

    /// Runs `work` (a wipe of the app's defaults, and `signedOut()`, which
    /// clears PostHog's own opt-out flag) and then puts the consent record
    /// back: the switch, when it was flipped, and the install date. Someone
    /// who turned analytics off and then chose Delete All Data stays off.
    /// Someone who never chose still has no stored choice afterwards.
    func preserveConsent(across work: () -> Void) {
        let wasEnabled = enabled
        let choice = defaults.object(forKey: Self.enabledKey) as? Bool
        let changedAt = defaults.object(forKey: Self.consentChangedAtKey)
        let installedAt = defaults.object(forKey: Self.installedAtKey)
        work()
        if let choice { defaults.set(choice, forKey: Self.enabledKey) }
        if let changedAt { defaults.set(changedAt, forKey: Self.consentChangedAtKey) }
        if let installedAt { defaults.set(installedAt, forKey: Self.installedAtKey) }
        enabled = wasEnabled
        if !wasEnabled { sink.setOptedOut(true) }
    }

    /// Sends the event with its safe properties. The guard can drop
    /// properties; it never blocks the event.
    func track(_ event: Event, _ properties: [String: AnalyticsValue] = [:]) {
        guard enabled else { return }
        var safe: [String: Any] = [:]
        for (key, value) in properties {
            if let reason = Self.violation(key: key, value: value) {
                #if DEBUG
                violations.append("\(event.rawValue).\(key)")
                #endif
                log.error("analytics: dropped \(event.rawValue, privacy: .public).\(key, privacy: .public) (\(reason, privacy: .public))")
                continue
            }
            safe[key] = value.any
        }
        sink.capture(event.rawValue, properties: safe)
    }

    func screen(_ name: String) {
        guard enabled else { return }
        sink.screen(name)
    }

    /// Once per install, with how long after install it happened
    /// (`hours_bucket`). Used for activation: the first purchase the app
    /// logged by itself. Never for sample data; callers skip test taps.
    func trackOnce(_ event: Event, _ properties: [String: AnalyticsValue] = [:]) {
        // Off: nothing is sent and the once-flag stays, so the event can
        // still fire if the switch comes back on.
        guard enabled, !isDemo() else { return }
        let key = "\(Self.activatedKey).\(event.rawValue)"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let installed = defaults.object(forKey: Self.installedAtKey) as? Date ?? .now
        let hours = Date.now.timeIntervalSince(installed) / 3600
        let bucket = switch hours {
        case ..<1: "under_1h"
        case ..<24: "under_24h"
        case ..<(24 * 7): "under_7d"
        default: "over_7d"
        }
        var all = properties
        all["hours_bucket"] = .string(bucket)
        track(event, all)
    }

    /// Identifies as sha256(accountSalt + provider + subject): the same id
    /// on every phone and after a reinstall.
    func signedIn(provider: String, subject: String) {
        signedIn(hash: Self.distinctId(salt: Self.accountSalt, provider: provider, subject: subject))
    }

    /// The same, with the hash already made (`AccountStore` makes it with
    /// `accountSalt`, so the two never disagree). Kept on the phone so a
    /// crash report sent on the next launch still carries it.
    func signedIn(hash: String) {
        identityBox.withLock { $0 = hash }
        defaults.set(hash, forKey: Self.identityHashKey)
        sink.identify(hash)
    }

    /// Sign-out and Delete All: back to an anonymous id.
    func signedOut() {
        identityBox.withLock { $0 = nil }
        defaults.removeObject(forKey: Self.identityHashKey)
        sink.reset()
    }

    /// Where analytics needs opt-in: the EU 27 (with its regions outside
    /// mainland Europe that have their own region codes), the rest of the
    /// EEA, the UK with its Crown dependencies and Gibraltar, and Switzerland.
    nonisolated static let optInRegions: Set<String> = [
        // EU 27
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
        "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        // EU regions with their own codes: French overseas regions, Saint
        // Martin, Åland, the Canary Islands, Ceuta and Melilla
        "GF", "GP", "MQ", "RE", "YT", "MF", "AX", "IC", "EA",
        // Rest of the EEA
        "IS", "LI", "NO",
        // UK, Crown dependencies, Gibraltar
        "GB", "GG", "JE", "IM", "GI",
        // Switzerland
        "CH",
    ]

    /// The switch before the user has touched it, from the iPhone's region
    /// (`Locale.current.region`): off where the law wants opt-in, and off
    /// when the region is unknown or not a country ("150" is Europe), on
    /// elsewhere.
    nonisolated static func defaultConsent(regionCode: String?) -> Bool {
        guard let code = regionCode?.uppercased(), code.count == 2,
              code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        return !optInRegions.contains(code)
    }

    /// sha256(salt + provider + subject) as 64 lowercase hex characters.
    nonisolated static func distinctId(salt: String, provider: String, subject: String) -> String {
        SHA256.hash(data: Data((salt + provider + subject).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Why a property must not leave the phone, or nil when it may.
    private static func violation(key: String, value: AnalyticsValue) -> String? {
        if deniedKeys.contains(key.lowercased()) { return "denied key" }
        guard case .string(let s) = value else { return nil }
        if s.range(of: moneyPattern, options: .regularExpression) != nil { return "looks like money" }
        if s.range(of: emailPattern, options: .regularExpression) != nil { return "looks like an email" }
        return nil
    }
}

// MARK: - Sinks

extension Analytics.Sink {
    func isFeatureEnabled(_ key: String) -> Bool { false }
    func setOptedOut(_ out: Bool) {}
}

/// No key in this build: nothing is sent anywhere.
final class NoopSink: Analytics.Sink {
    func capture(_ name: String, properties: [String: Any]) {}
    func identify(_ id: String) {}
    func reset() {}
    func screen(_ name: String) {}
}

/// The real thing. Session replay off, element autocapture off until the
/// audit in the spec passes, screen views sent by hand (`Analytics.screen`)
/// so only named screens are counted.
///
/// With sharing off at launch the SDK is not set up at all: set up, even
/// opted out, it still fetches its remote config and feature flags. It is
/// set up the first time the switch goes on.
final class PostHogSink: Analytics.Sink {
    static let defaultHost = "https://eu.i.posthog.com"

    private let apiKey: String
    private let host: URL
    private var isSetUp = false

    init(apiKey: String, host: URL, enabled: Bool) {
        self.apiKey = apiKey
        self.host = host
        if enabled {
            setUp()
        } else {
            log.notice("analytics: sharing is off, PostHog not set up")
        }
    }

    private func setUp() {
        guard !isSetUp else { return }
        isSetUp = true
        // `init(apiKey:host:)` is deprecated in 3.82; same thing, new name.
        let config = PostHogConfig(projectToken: apiKey, host: host.absoluteString)
        config.sessionReplay = false
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.personProfiles = .always
        config.preloadFeatureFlags = true
        // Crashes are Sentry's (CrashReporting.swift), not PostHog's. Off by
        // default in 3.82; set here so a later default cannot switch it on.
        config.errorTrackingConfig.autoCapture = false
        // Only set up with sharing on. A stored SDK opt-out from an earlier
        // "off" is cleared by `setOptedOut(false)` right after.
        config.optOut = false
        PostHogSDK.shared.setup(config)
    }

    // Before set-up (sharing off since launch) there is nothing to send to;
    // the facade already drops events while off.
    func capture(_ name: String, properties: [String: Any]) {
        guard isSetUp else { return }
        PostHogSDK.shared.capture(name, properties: properties)
    }

    func identify(_ id: String) {
        guard isSetUp else { return }
        PostHogSDK.shared.identify(id)
    }

    func reset() {
        guard isSetUp else { return }
        PostHogSDK.shared.reset()
    }

    func screen(_ name: String) {
        guard isSetUp else { return }
        PostHogSDK.shared.screen(name)
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        guard isSetUp else { return false }
        return PostHogSDK.shared.isFeatureEnabled(key)
    }

    func setOptedOut(_ out: Bool) {
        if out {
            guard isSetUp else { return }
            PostHogSDK.shared.optOut()
        } else {
            setUp()
            PostHogSDK.shared.optIn()
        }
    }
}
