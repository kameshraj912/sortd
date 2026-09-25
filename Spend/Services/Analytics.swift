import Foundation
import CryptoKit
import Observation
import PostHog

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
/// `signedIn` identifies as sha256(salt + provider + subject), where the salt
/// is random and kept only on this phone, so the id never carries the email
/// or the raw subject. `signedOut` resets.
///
/// Consent: on by default (Settings › Privacy has the switch). Turning it
/// off sends `analytics_opted_out` once, then nothing.
@MainActor @Observable
final class Analytics {
    enum Event: String, CaseIterable {
        case setupStarted = "setup_started"
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
        case backupCompleted = "backup_completed"
        case restoreCompleted = "restore_completed"
        case analyticsOptedOut = "analytics_opted_out"
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
    static let saltKey = "analyticsSalt"
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
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        guard !key.isEmpty, let hostURL = URL(string: host.isEmpty ? PostHogSink.defaultHost : host) else {
            log.notice("analytics off: no key (POSTHOG_API_KEY is empty), nothing is sent")
            return Analytics(sink: NoopSink(), defaults: .standard)
        }
        let sink = PostHogSink(apiKey: key, host: hostURL, enabled: enabled)
        log.info("analytics on: PostHog at \(hostURL.host() ?? host, privacy: .public), sharing \(enabled ? "on" : "off", privacy: .public)")
        return Analytics(sink: sink, defaults: .standard)
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
    /// Mirrors the persisted flag so SwiftUI sees the switch change.
    private var enabled: Bool

    /// Privacy guard trail, for tests: "event.key" per property dropped.
    private(set) var violations: [String] = []

    init(sink: Sink, defaults: UserDefaults) {
        self.sink = sink
        self.defaults = defaults
        self.enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if defaults.object(forKey: Self.installedAtKey) == nil {
            defaults.set(Date.now, forKey: Self.installedAtKey)
        }
    }

    /// Persisted at `analyticsEnabled`, default true. Off sends the one
    /// opt-out event on the transition, then `track` and `screen` do nothing
    /// until it is on again. Off while already off does nothing.
    var isEnabled: Bool {
        get { enabled }
        set {
            guard newValue != enabled else { return }
            if newValue {
                enabled = true
                defaults.set(true, forKey: Self.enabledKey)
                (sink as? PostHogSink)?.optIn()
            } else {
                // Sent while still enabled, so the sink takes it.
                sink.capture(Event.analyticsOptedOut.rawValue, properties: [:])
                enabled = false
                defaults.set(false, forKey: Self.enabledKey)
                (sink as? PostHogSink)?.optOut()
            }
        }
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
        let key = "\(Self.activatedKey).\(event.rawValue)"
        guard !DemoData.isActive, !defaults.bool(forKey: key) else { return }
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

    /// Identifies as a salted hash. The salt is made once and kept on the
    /// phone, so the id is stable across launches and useless off it.
    func signedIn(provider: String, subject: String) {
        let salt: String
        if let kept = defaults.string(forKey: Self.saltKey), kept.count == 64 {
            salt = kept
        } else {
            salt = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
            defaults.set(salt, forKey: Self.saltKey)
        }
        sink.identify(Self.distinctId(salt: salt, provider: provider, subject: subject))
    }

    /// Sign-out and Delete All: back to an anonymous id.
    func signedOut() {
        sink.reset()
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
final class PostHogSink: Analytics.Sink {
    static let defaultHost = "https://eu.i.posthog.com"

    init(apiKey: String, host: URL, enabled: Bool) {
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
        // The switch was off last time: the SDK must not send lifecycle
        // events before the facade has a chance to say so.
        config.optOut = !enabled
        PostHogSDK.shared.setup(config)
    }

    func capture(_ name: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(name, properties: properties)
    }

    func identify(_ id: String) { PostHogSDK.shared.identify(id) }
    func reset() { PostHogSDK.shared.reset() }
    func screen(_ name: String) { PostHogSDK.shared.screen(name) }
    func isFeatureEnabled(_ key: String) -> Bool { PostHogSDK.shared.isFeatureEnabled(key) }

    func optIn() { PostHogSDK.shared.optIn() }
    func optOut() { PostHogSDK.shared.optOut() }
}
