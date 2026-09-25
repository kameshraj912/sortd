import Testing
import Foundation
import Sentry
@testable import Spend

/// Pins the contract for overhaul sub-spec 2b: Sentry crash reports in the live
/// app, scrubbed. `CrashReporting.enabled` decides whether reporting runs at
/// all; `CrashReporting.scrub` and `CrashReporting.scrubBreadcrumb` decide what
/// leaves the phone. Both are pure so they can be pinned without starting the
/// SDK or touching the network.
struct CrashReportingTests {

    // MARK: - enabled(isDebug:dsn:consent:)

    @Test func onInReleaseWithDsnAndConsent() {
        #expect(CrashReporting.enabled(isDebug: false, dsn: "https://x@o.ingest.sentry.io/1", consent: true) == true)
    }

    @Test func offWithoutConsent() {
        #expect(CrashReporting.enabled(isDebug: false, dsn: "https://x@o.ingest.sentry.io/1", consent: false) == false)
    }

    @Test func offWithEmptyDsn() {
        #expect(CrashReporting.enabled(isDebug: false, dsn: "", consent: true) == false)
    }

    @Test func offInDebugEvenWithDsnAndConsent() {
        #expect(CrashReporting.enabled(isDebug: true, dsn: "https://x@o.ingest.sentry.io/1", consent: true) == false)
    }

    // MARK: - scrub(_:userId:)

    /// Builds the event described in the sub-spec 2b test plan: an exception
    /// value and a message that both carry merchant text and an amount, a user
    /// with an IP address and email, a request, breadcrumbs, extra and tags.
    /// Also what the crash converter adds for an uncaught NSException: its
    /// userInfo under `context["user info"]`, and earlier runtime messages
    /// under `mechanism.data["crash_info_messages"]`.
    private func makeEvent() -> Sentry.Event {
        let event = Sentry.Event(level: .error)

        let exception = Sentry.Exception(value: "Bad amount at Coles 12.50", type: "DecodingError")
        let frame = Sentry.Frame()
        frame.function = "parseReceipt(_:)"
        let stacktrace = Sentry.SentryStacktrace(frames: [frame], registers: [:])
        exception.stacktrace = stacktrace
        let mechanism = Sentry.Mechanism(type: "nsexception")
        mechanism.handled = false
        mechanism.data = ["crash_info_messages": ["Fatal error: Coles 12.50 refund failed"]]
        exception.mechanism = mechanism
        event.exceptions = [exception]

        event.context = [
            "user info": ["NSLocalizedDescription": "Receipt from Coles for 12.50 to a@b.c"],
            "device": ["model": "iPhone17,1"],
            "os": ["name": "iOS", "version": "26.0"],
            "app": ["app_version": "1.0"],
        ]

        event.message = Sentry.SentryMessage(formatted: "Coles 12.50 failed")

        let user = Sentry.User(userId: "abc")
        user.ipAddress = "1.2.3.4"
        user.email = "a@b.c"
        event.user = user

        event.request = Sentry.SentryRequest()
        let crumb = Sentry.Breadcrumb(level: .info, category: "http")
        crumb.message = "GET /coles"
        event.breadcrumbs = [crumb]
        event.extra = ["merchant": "Coles"]
        event.tags = ["merchant": "Coles"]

        return event
    }

    @Test func scrubDropsTheExceptionValueButKeepsTypeAndFrame() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        let exception = scrubbed.exceptions?.first
        #expect(exception?.value == nil || exception?.value == "")
        #expect(exception?.type == "DecodingError")
        #expect(exception?.stacktrace?.frames.count == 1)
        #expect(exception?.stacktrace?.frames.first?.function == "parseReceipt(_:)")
    }

    /// The converter puts an uncaught NSException's userInfo under
    /// `context["user info"]`; it goes. Device, OS and app stay, since Sentry
    /// groups on them and they carry nothing typed in the app.
    @Test func scrubDropsTheNSExceptionUserInfoButKeepsDeviceOsAndApp() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        #expect(scrubbed.context?["user info"] == nil)
        #expect(scrubbed.context?["device"]?["model"] as? String == "iPhone17,1")
        #expect(scrubbed.context?["os"]?["name"] as? String == "iOS")
        #expect(scrubbed.context?["app"]?["app_version"] as? String == "1.0")
    }

    /// `mechanism.data` carries earlier Swift runtime messages
    /// ("crash_info_messages"); it goes. The mechanism type and handled flag stay.
    @Test func scrubDropsTheMechanismDataButKeepsItsType() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        let mechanism = scrubbed.exceptions?.first?.mechanism
        #expect(mechanism?.data == nil)
        #expect(mechanism?.type == "nsexception")
        #expect(mechanism?.handled == false)
    }

    @Test func scrubDropsTheMessage() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        #expect(scrubbed.message == nil)
    }

    @Test func scrubKeepsOnlyTheHashAsUserId() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        #expect(scrubbed.user?.userId == "deadbeef")
        #expect(scrubbed.user?.ipAddress == nil)
        #expect(scrubbed.user?.email == nil)
    }

    @Test func scrubWithNoUserIdLeavesUserNil() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: nil)
        #expect(scrubbed.user == nil)
    }

    @Test func scrubClearsRequestBreadcrumbsExtraAndTags() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        #expect(scrubbed.request == nil)
        #expect(scrubbed.breadcrumbs == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.tags == nil)
    }

    /// The serialised payload of a scrubbed event must carry no merchant name,
    /// no amount, no IP address and no email — nothing that could identify a
    /// person or a purchase.
    @Test func scrubbedEventSerialisesWithNoUserText() {
        let scrubbed = CrashReporting.scrub(makeEvent(), userId: "deadbeef")
        let dict = scrubbed.serialize()
        let flattened = String(describing: dict)

        #expect(!flattened.contains("Coles"))
        #expect(!flattened.contains("12.50"))
        #expect(!flattened.contains("1.2.3.4"))
        #expect(!flattened.contains("@"))
        #expect(!flattened.contains("refund"))
        #expect(!flattened.contains("Receipt from"))
        #expect(!flattened.contains("user info"))
        #expect(!flattened.contains("crash_info_messages"))
    }

    // MARK: - identityHash survives a relaunch

    /// Crash events are sent on the next launch, so the hash must come back
    /// from disk with a fresh `Analytics` on the same defaults, and go on
    /// `signedOut`.
    @MainActor @Test func identityHashPersistsAcrossInstancesAndClearsOnSignOut() {
        let suite = "CrashReportingTests.identityHash"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = Analytics(sink: SpySink(), defaults: defaults)
        #expect(first.identityHash == nil)
        first.signedIn(provider: "apple", subject: "001.abc")
        let hash = first.identityHash
        #expect(hash?.count == 64)

        let second = Analytics(sink: SpySink(), defaults: defaults)
        #expect(second.identityHash == hash)

        second.signedOut()
        #expect(second.identityHash == nil)
        let third = Analytics(sink: SpySink(), defaults: defaults)
        #expect(third.identityHash == nil)
    }

    // MARK: - scrubBreadcrumb(_:)

    @Test func scrubBreadcrumbDropsEveryBreadcrumb() {
        let httpCrumb = Sentry.Breadcrumb(level: .info, category: "http")
        let navCrumb = Sentry.Breadcrumb(level: .info, category: "navigation")
        let uiCrumb = Sentry.Breadcrumb(level: .info, category: "ui.click")

        #expect(CrashReporting.scrubBreadcrumb(httpCrumb) == nil)
        #expect(CrashReporting.scrubBreadcrumb(navCrumb) == nil)
        #expect(CrashReporting.scrubBreadcrumb(uiCrumb) == nil)
    }
}
