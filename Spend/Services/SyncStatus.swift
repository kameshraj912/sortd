import SwiftUI

/// What a slow job (connecting Gmail, a sync) is doing right now, in plain
/// words, so the screen never just spins. One shared copy per job: the
/// Connect sheet, Settings and Home all read the same one, so the work
/// carries on and stays visible when the person leaves the screen.
@MainActor @Observable
final class SyncStatus {
    static let gmail: SyncStatus = {
        let s = SyncStatus()
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["SPEND_SYNC_DEMO"] { s.showDemo(name) }
        #endif
        return s
    }()

    #if DEBUG
    /// Debug: SPEND_SYNC_DEMO=signin|connecting|searching|adding|done|offline|expired
    /// holds that step on screen, for screenshots. Syncs don't run while it's set.
    static let demoActive = ProcessInfo.processInfo.environment["SPEND_SYNC_DEMO"] != nil

    private func showDemo(_ name: String) {
        quiet = false
        phase = switch name {
        case "signin": .signingIn
        case "connecting": .connecting
        case "searching": .searching(found: 214)
        case "adding": .adding(done: 87, total: 214, added: 31)
        case "done": .finished(added: 64)
        case "offline": .failed(SyncFailure(kind: .offline, message: "You're offline. Connect to the internet and try again."))
        case "expired": .failed(SyncFailure(kind: .expired, message: "Google access has ended. Connect Gmail again."))
        default: .idle
        }
    }
    #endif

    enum Phase: Equatable {
        case idle
        case signingIn
        case connecting
        case searching(found: Int)
        case adding(done: Int, total: Int, added: Int)
        case finished(added: Int)
        case failed(SyncFailure)

        /// Done or stopped: what's left on screen once the work is over.
        var isEnd: Bool {
            switch self {
            case .finished, .failed: true
            default: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// Automatic syncs (the app opening) stay out of the way unless there is
    /// something to add or something the person must fix.
    private(set) var quiet = false
    /// The job itself, kept here so closing a screen doesn't stop it.
    var task: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .signingIn, .connecting, .searching, .adding: true
        default: false
        }
    }

    var title: String {
        switch phase {
        case .idle: ""
        case .signingIn: "Opening Google sign-in…"
        case .connecting: "Connecting your Gmail…"
        case .searching(let found): found == 0 ? "Looking for receipts…" : "Looking for receipts… (found \(found))"
        case .adding(let done, let total, _): "Adding purchases… \(done) of \(total) emails checked"
        case .finished(let added): added == 0 ? "Done. No new purchases." : "Done. \(added) \(added == 1 ? "purchase" : "purchases") added."
        case .failed(let f): f.message
        }
    }

    /// 0…1 when the amount of work is known, nil for "working".
    var fraction: Double? {
        if case .adding(let done, let total, _) = phase, total > 0 { return Double(done) / Double(total) }
        return nil
    }

    /// Whether Home should show the small status line.
    var showsOnHome: Bool {
        switch phase {
        case .idle: false
        case .signingIn: false
        case .connecting, .searching: !quiet
        case .adding: true
        case .finished(let added): !quiet || added > 0
        case .failed(let f): !quiet || f.kind == .expired || f.kind == .accessDenied
        }
    }

    private var lastAnnounced = ""
    private var lastQuarter = -1
    private var clearTask: Task<Void, Never>?

    /// Which job owns the status. A newer job (the person tapping Connect
    /// while the app's own sync runs) takes over; the older one's updates
    /// are then ignored, so two jobs never fight over one line of text.
    private(set) var job = 0

    /// Claims the status for a new job and returns its number.
    @discardableResult
    func begin(quiet: Bool) -> Int {
        job += 1
        self.quiet = quiet
        return job
    }

    /// The person asked for what the app was already doing quietly: show it.
    func promote() { quiet = false }

    /// Busy with something the person started (not a quiet background sync).
    var isBusyForPerson: Bool { isBusy && !quiet }

    func update(_ next: Phase, job owner: Int? = nil) {
        if let owner, owner != job { return }
        guard next != phase else { return }
        phase = next
        clearTask?.cancel()
        announce()
        // "Done" fades by itself; errors stay until dismissed or retried.
        if case .finished = next {
            clearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self, case .finished = self.phase else { return }
                self.phase = .idle
            }
        }
    }

    func dismiss() {
        clearTask?.cancel()
        phase = .idle
        quiet = false
    }

    /// VoiceOver hears each new step, and progress every quarter, not every email.
    private func announce() {
        let key: String
        switch phase {
        case .idle: lastQuarter = -1; return
        case .searching: key = "searching"
        case .adding:
            let q = Int((fraction ?? 0) * 4)
            guard q != lastQuarter else { return }
            lastQuarter = q
            key = "adding-\(q)"
        default: key = title
        }
        guard key != lastAnnounced, !(quiet && !showsOnHome) else { return }
        lastAnnounced = key
        AccessibilityNotification.Announcement(title).post()
    }
}

/// Why a job stopped, in one short sentence, with what to do next.
struct SyncFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case offline, accessDenied, expired, slowDown, google }
    let kind: Kind
    let message: String

    /// Access ended or was never given: signing in again is the fix.
    var needsSignIn: Bool { kind == .expired || kind == .accessDenied }
    var retryTitle: String { needsSignIn ? "Connect Again" : "Try Again" }

    static func from(_ error: Error) -> SyncFailure {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                 .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return SyncFailure(kind: .offline, message: "You're offline. Connect to the internet and try again.")
            default: break
            }
        }
        if let g = error as? GmailError {
            if g.code == 401 || g.body.contains("invalid_grant") {
                return SyncFailure(kind: .expired, message: "Google access has ended. Connect Gmail again.")
            }
            if g.body.contains("insufficient") {
                return SyncFailure(kind: .accessDenied, message: "Sortd can't read receipts. Connect again and tick the Gmail box.")
            }
            if g.code == 429 || g.body.contains("rateLimit") || g.body.contains("Quota exceeded") {
                return SyncFailure(kind: .slowDown, message: "Gmail asked Sortd to slow down. What's read is saved. Try again in a minute.")
            }
            return SyncFailure(kind: .google, message: "Gmail had a problem. Try again in a moment.")
        }
        if let a = error as? GoogleAuth.AuthError {
            switch a {
            case .missingGmailAccess:
                return SyncFailure(kind: .accessDenied, message: "Sortd needs the Gmail box ticked to read receipts.")
            case .noRefreshToken:
                return SyncFailure(kind: .expired, message: "Google access has ended. Connect Gmail again.")
            case .server(let text) where text.contains("ended"):
                return SyncFailure(kind: .expired, message: "Google access has ended. Connect Gmail again.")
            default:
                return SyncFailure(kind: .google, message: "Google didn't finish signing in. Try again.")
            }
        }
        return SyncFailure(kind: .google, message: "Something went wrong. Try again.")
    }
}
