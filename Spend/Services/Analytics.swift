import Foundation
import CryptoKit
import Observation
import PostHog
import os

/// The one door to PostHog. Nothing else in the app calls the SDK; every
/// screen goes through `Analytics.shared`, which sends named events with
/// scalar properties to a `Sink`. Tests give it a fake sink.
///
/// What is never sent: amounts, merchants, emails, notes or card digits.
/// A privacy guard drops a property whose key is
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
        case applePayTapLogged = "apple_pay_tap_logged"
        /// One per Shortcuts run that reaches Sortd (8 Oct 2026), saved or
        /// not, so a run that logged nothing still says why. `kind` is
        /// tap|notification, `result` is saved|merged|needs_check|blank|
        /// no_amount|not_completed|money_in|not_purchase (a bank app's
        /// notification that is not a purchase)|refund|health_check|queued|
        /// not_saved, and `has_amount`/`has_shop`/`has_card`/`has_title`/
        /// `has_subtitle`/`has_body`/`has_text` say which fields arrived.
        /// Never an amount, a shop or a card name
        /// (`LogWalletTapIntent.runEvent`).
        case applePayRun = "apple_pay_run"
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
        /// The beta's extra intent events (docs/specs/2026-09-25-free-app-overhaul-2-analytics.md).
        /// Never amounts, merchants, emails or notes.
        case searchUsed = "search_used"
        case receiptScanned = "receipt_scanned"
        case statementImported = "statement_imported"
        case budgetSet = "budget_set"
        /// `category` is the `SpendCategory` name only, never the limit amount.
        case categoryLimitSet = "category_limit_set"
        case insightsRangeChanged = "insights_range_changed"
        case purchaseEdited = "purchase_edited"
        /// `from` and `to` are `SpendCategory` names.
        case categoryChanged = "category_changed"
        case cardAdded = "card_added"
        case appLockTurnedOn = "app_lock_turned_on"
        case helpOpened = "help_opened"
        /// Every tap on the Apple Pay setup step (6 Oct 2026): both iOS 26
        /// testers tapped out of it and the named steps alone could not say
        /// where. `action` names the button, `route` the iOS route, `step`
        /// how far the setup had got (`ApplePaySetupSteps.Progress`).
        case applePaySetupAction = "apple_pay_setup_action"
        /// The hidden developer menu (Settings › About, 7 taps): a forced
        /// event so Raj can see one arrive in PostHog on demand.
        case developerTestEvent = "developer_test_event"
        /// The founder's note (`FounderNoteSheet`): `moment` is `aha` (the
        /// first automatic purchase) or `about` (replayed from Settings).
        case founderNoteSeen = "founder_note_seen"
        case founderNoteReplyTapped = "founder_note_reply_tapped"
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
        /// which `reset()` wipes). `identity` is the signed-in hash, or nil
        /// when signed out: turning sharing on brings the SDK's person in
        /// line with it, since identify and reset calls made while sharing
        /// was off never reached the SDK. Optional; a spy leaves it out.
        func setOptedOut(_ out: Bool, identity: String?)
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
        // One answer for the SDK and the facade: both come from here.
        let enabled = startingConsent(defaults: .standard, regionCode: region)
        // A host with no scheme is a broken xcconfig line ("//" is a comment
        // there): fall back to the EU host rather than send to nowhere.
        let hostText = host.contains("://") ? host : PostHogSink.defaultHost
        guard !key.isEmpty, let hostURL = URL(string: hostText) else {
            log.notice("analytics off: no key (POSTHOG_API_KEY is empty), nothing is sent")
            return Analytics(sink: NoopSink(), defaults: .standard, regionCode: region)
        }
        let sink = PostHogSink(apiKey: key, host: hostURL, enabled: enabled,
                               identity: keptIdentity(in: .standard))
        log.info("analytics on: PostHog at \(hostURL.host() ?? host, privacy: .public), sharing \(enabled ? "on" : "off", privacy: .public)")
        return Analytics(sink: sink, defaults: .standard, regionCode: region)
    }()

    /// Call once at launch so the SDK starts (and logs) before any event.
    static func start() { _ = shared }

    /// A PostHog feature flag, for A/B tests between shipped screens only
    /// (never to switch on hidden features: guideline 2.3.1, see Features).
    /// Unknown, offline or no key: false.
    static func flag(_ key: String) -> Bool { shared.sink.isFeatureEnabled(key) }

    /// The PostHog host this build talks to (Settings › About's hidden
    /// developer menu). Recomputed from the same Info.plist key `shared`
    /// reads, so the two can never drift apart.
    static var postHogHost: String {
        let host = (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hostText = host.contains("://") ? host : PostHogSink.defaultHost
        return URL(string: hostText)?.host() ?? hostText
    }

    /// Whether this build was compiled with session replay at all
    /// (`SORTD_REPLAY`). Replay also needs consent (`isEnabled`) and a copy
    /// that is not from the App Store (`replayAllowed`); the developer menu
    /// shows them together.
    static var replayBuildFlagOn: Bool {
        #if SORTD_REPLAY
        true
        #else
        false
        #endif
    }

    /// Replay is for TestFlight only (Raj, 26 Sep 2026). Since 6 Oct 2026
    /// the Release build carries the flag too, so testers' builds record;
    /// the App Store copy of the same binary is told apart by its receipt.
    /// Gated on the TestFlight receipt being there, not on the App Store
    /// one being absent, so a copy with no receipt at all never records.
    /// The simulator has no receipt: Debug builds keep replay there.
    static var replayAllowed: Bool {
        replayAllowed(flagOn: replayBuildFlagOn, isTestFlight: Distribution.isTestFlight)
    }

    static func replayAllowed(flagOn: Bool, isTestFlight: Bool) -> Bool {
        guard flagOn else { return false }
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }

    // MARK: - Instance

    private let sink: Sink
    private let defaults: UserDefaults
    /// Sample data is loaded: `trackOnce` (activation) must not count it.
    private let isDemo: @MainActor () -> Bool
    /// Mirrors the persisted flag so SwiftUI sees the switch change.
    private var enabled: Bool

    /// Privacy guard trail, for tests: "event.key" per property dropped.
    private(set) var violations: [String] = []

    /// `trackOncePerSession`'s memory: in-memory only, so it starts empty
    /// every launch (there is no other notion of "session" here).
    private var sessionFired: Set<Event> = []

    /// The identified id (the salted hash) while signed in, else nil. Read
    /// by `CrashReporting` from Sentry's own thread, so it sits behind a
    /// lock rather than on the main actor. Persisted at `identityHashKey`:
    /// Sentry sends a crash on the next launch, after this object is new.
    nonisolated var identityHash: String? { identityBox.withLock { $0 } }
    private nonisolated let identityBox = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// `regionCode` is the iPhone's region (`Locale.current.region`), for
    /// the default consent until the user chooses.
    init(sink: Sink, defaults: UserDefaults, isDemo: @escaping @MainActor () -> Bool = { DemoData.isActive },
         regionCode: String?) {
        self.sink = sink
        self.defaults = defaults
        self.isDemo = isDemo
        self.enabled = Self.startingConsent(defaults: defaults, regionCode: regionCode)
        if let kept = Self.keptIdentity(in: defaults) {
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
                sink.setOptedOut(false, identity: identityHash)
            } else {
                // Sent while still enabled, so the sink takes it.
                sink.capture(Event.analyticsOptedOut.rawValue, properties: [:])
                enabled = false
                defaults.set(false, forKey: Self.enabledKey)
                sink.setOptedOut(true, identity: identityHash)
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
        let choice = Self.storedChoice(in: defaults)
        let changedAt = defaults.object(forKey: Self.consentChangedAtKey)
        let installedAt = defaults.object(forKey: Self.installedAtKey)
        work()
        if let choice { defaults.set(choice, forKey: Self.enabledKey) }
        if let changedAt { defaults.set(changedAt, forKey: Self.consentChangedAtKey) }
        if let installedAt { defaults.set(installedAt, forKey: Self.installedAtKey) }
        enabled = wasEnabled
        if !wasEnabled { sink.setOptedOut(true, identity: identityHash) }
    }

    /// The user's own choice, or nil when they never flipped the switch.
    /// A stored value counts only with its `consentChangedAtKey` date:
    /// older builds wrote `true` on Delete All without anyone choosing.
    static func storedChoice(in defaults: UserDefaults) -> Bool? {
        guard defaults.object(forKey: consentChangedAtKey) != nil else { return nil }
        return defaults.object(forKey: enabledKey) as? Bool
    }

    /// The switch at launch: the user's choice, else the region's default.
    static func startingConsent(defaults: UserDefaults, regionCode: String?) -> Bool {
        storedChoice(in: defaults) ?? defaultConsent(regionCode: regionCode)
    }

    /// The signed-in hash kept from an earlier launch, if any.
    static func keptIdentity(in defaults: UserDefaults) -> String? {
        guard let kept = defaults.string(forKey: identityHashKey), kept.count == 64 else { return nil }
        return kept
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

    /// Like `track`, but only the first time this event is asked for since
    /// launch (`searchUsed`: "first character typed, once per session").
    /// Off: nothing is sent and nothing is marked fired, so it can still
    /// fire once consent comes back on.
    func trackOncePerSession(_ event: Event, _ properties: [String: AnalyticsValue] = [:]) {
        guard enabled, !sessionFired.contains(event) else { return }
        sessionFired.insert(event)
        track(event, properties)
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
    func setOptedOut(_ out: Bool, identity: String?) {}
}

/// No key in this build: nothing is sent anywhere.
final class NoopSink: Analytics.Sink {
    func capture(_ name: String, properties: [String: Any]) {}
    func identify(_ id: String) {}
    func reset() {}
    func screen(_ name: String) {}
}

/// The PostHog calls `PostHogSink` makes, so tests can stand in for the SDK.
protocol PostHogClient: AnyObject {
    func setup(apiKey: String, host: URL)
    /// The SDK's current person: its anonymous id, or the identified hash.
    var distinctId: String { get }
    func capture(_ name: String, properties: [String: Any])
    func identify(_ id: String)
    func reset()
    func screen(_ name: String)
    func isFeatureEnabled(_ key: String) -> Bool
    func optIn()
    func optOut()
}

/// The real thing. Session replay on only in a `SORTD_REPLAY` build (the
/// beta), off for the App Store release. Element autocapture off until the
/// audit in the spec passes, screen views sent by hand (`Analytics.screen`)
/// so only named screens are counted.
///
/// With sharing off at launch the SDK is not set up at all: set up, even
/// opted out, it still fetches its remote config and feature flags. It is
/// set up the first time sharing goes on.
///
/// Replay and consent: `PostHogSDK.optOut()` uninstalls the replay
/// integration (and `optIn()` reinstalls it), so `Analytics.isEnabled =
/// false` already stops recording; nothing extra is needed here.
final class PostHogSink: Analytics.Sink {
    static let defaultHost = "https://eu.i.posthog.com"

    private let apiKey: String
    private let host: URL
    private let client: PostHogClient
    private var isSetUp = false

    init(apiKey: String, host: URL, enabled: Bool, identity: String?,
         client: PostHogClient = LivePostHogClient()) {
        self.apiKey = apiKey
        self.host = host
        self.client = client
        if enabled {
            turnOn(identity: identity)
        } else {
            log.notice("analytics: sharing is off, PostHog not set up")
        }
    }

    /// Sets the SDK up (once), clears any opt-out it kept from an earlier
    /// "off", then brings its person in line with `identity`.
    private func turnOn(identity: String?) {
        if !isSetUp {
            isSetUp = true
            client.setup(apiKey: apiKey, host: host)
        }
        client.optIn()
        Self.reconcile(client, identity: identity)
    }

    /// While sharing was off the SDK missed any sign-in, sign-out or Delete
    /// All. Signed in: identify as the hash unless the SDK already is it.
    /// Signed out but the SDK still carries a hash (64 hex): reset, so a
    /// deleted person does not come back.
    static func reconcile(_ client: PostHogClient, identity: String?) {
        let current = client.distinctId
        if let identity {
            if current != identity { client.identify(identity) }
        } else if looksIdentified(current) {
            client.reset()
        }
    }

    /// The signed-in id is sha256 as 64 lowercase hex; PostHog's own
    /// anonymous ids are UUIDs.
    static func looksIdentified(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
    }

    // Before set-up (sharing off since launch) there is nothing to send to;
    // the facade already drops events while off.
    func capture(_ name: String, properties: [String: Any]) {
        guard isSetUp else { return }
        client.capture(name, properties: properties)
    }

    func identify(_ id: String) {
        guard isSetUp else { return }
        client.identify(id)
    }

    func reset() {
        guard isSetUp else { return }
        client.reset()
    }

    func screen(_ name: String) {
        guard isSetUp else { return }
        client.screen(name)
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        guard isSetUp else { return false }
        return client.isFeatureEnabled(key)
    }

    func setOptedOut(_ out: Bool, identity: String?) {
        if out {
            guard isSetUp else { return }
            client.optOut()
        } else {
            turnOn(identity: identity)
        }
    }
}

/// `PostHogClient` on the real SDK.
final class LivePostHogClient: PostHogClient {
    func setup(apiKey: String, host: URL) {
        // `init(apiKey:host:)` is deprecated in 3.82; same thing, new name.
        let config = PostHogConfig(projectToken: apiKey, host: host.absoluteString)
        // Session replay: beta only (SORTD_REPLAY), off for the App Store
        // release. Screenshot mode, not wireframes, since this is SwiftUI;
        // text, images and sandboxed pickers are masked wholesale, and the
        // few money/shop views left get an explicit `.postHogMask()`.
        // The flag alone is not enough: the same Release binary goes to
        // TestFlight and the App Store, and only the first may record.
        if Analytics.replayAllowed {
            config.sessionReplay = true
            config.sessionReplayConfig.screenshotMode = true
            config.sessionReplayConfig.maskAllTextInputs = true
            config.sessionReplayConfig.maskAllImages = true
            config.sessionReplayConfig.maskAllSandboxedViews = true
            config.sessionReplayConfig.throttleDelay = 1
        } else {
            config.sessionReplay = false
        }
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.personProfiles = .always
        config.preloadFeatureFlags = true
        // Crashes are Sentry's (CrashReporting.swift), not PostHog's. Off by
        // default in 3.82; set here so a later default cannot switch it on.
        config.errorTrackingConfig.autoCapture = false
        // Only set up with sharing on. A stored SDK opt-out from an earlier
        // "off" is cleared by the `optIn()` that follows.
        config.optOut = false
        PostHogSDK.shared.setup(config)
    }

    var distinctId: String { PostHogSDK.shared.getDistinctId() }
    func capture(_ name: String, properties: [String: Any]) { PostHogSDK.shared.capture(name, properties: properties) }
    func identify(_ id: String) { PostHogSDK.shared.identify(id) }
    func reset() { PostHogSDK.shared.reset() }
    func screen(_ name: String) { PostHogSDK.shared.screen(name) }
    func isFeatureEnabled(_ key: String) -> Bool { PostHogSDK.shared.isFeatureEnabled(key) }
    func optIn() { PostHogSDK.shared.optIn() }
    func optOut() { PostHogSDK.shared.optOut() }
}
