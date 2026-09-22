import Foundation
import OSLog

/// Timing marks for the slow parts of Sortd: launch, sign-in, each Gmail
/// sync phase, exchange rates, the widget and statement imports.
///
/// Signposts show up in Instruments (Points of Interest / os_signpost,
/// subsystem `com.kameshraj.spend`, category `perf`). The same durations go
/// to the unified log at debug level, which costs next to nothing when no
/// one is watching:
/// `log stream --level debug --predicate 'subsystem == "com.kameshraj.spend" && category == "perf"'`
nonisolated enum Perf {
    static let signposter = OSSignposter(subsystem: "com.kameshraj.spend", category: "perf")
    static let logger = Logger(subsystem: "com.kameshraj.spend", category: "perf")

    /// When the process started, for "launch to first frame".
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return .now }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }()

    /// A running measurement. Call `end()` once.
    struct Span: Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant

        /// Ends the span and returns its length in milliseconds.
        @discardableResult
        func end(_ detail: String = "") -> Double {
            Perf.signposter.endInterval(name, state)
            let ms = Perf.ms(since: start)
            Perf.logger.debug("\(name, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms \(detail, privacy: .public)")
            return ms
        }
    }

    static func begin(_ name: StaticString) -> Span {
        Span(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()), start: .now)
    }

    /// Times `work`, sync or async.
    static func measure<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let span = begin(name)
        defer { span.end() }
        return try await work()
    }

    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let span = begin(name)
        defer { span.end() }
        return try work()
    }

    /// A single moment worth marking (first frame, first purchase shown).
    static func mark(_ name: StaticString, _ detail: String = "") {
        signposter.emitEvent(name)
        logger.debug("\(name, privacy: .public) \(detail, privacy: .public)")
    }

    static func ms(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

extension Perf {
    @MainActor private static var sawFirstActive = false

    /// Once per process: the first time the app is on screen and active,
    /// roughly "tap the icon → first frame".
    @MainActor static func markFirstActive() {
        guard !sawFirstActive else { return }
        sawFirstActive = true
        let ms = Date.now.timeIntervalSince(processStart) * 1000
        mark("launch.firstActive", String(format: "%.0f ms after process start", ms))
    }
}
