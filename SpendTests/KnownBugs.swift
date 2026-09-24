import Testing
import Foundation

/// A test that documents a real, unfixed bug. It is compiled always and runs
/// only when SORTD_KNOWN_BUGS=1 reaches the test process (scripts/test.sh
/// --known-bugs). CI never sets it, so CI stays green while the bug list
/// stays in the repo. Fixing a bug means removing its tag and trait.
enum KnownBugs {
    static var run: Bool { ProcessInfo.processInfo.environment["SORTD_KNOWN_BUGS"] == "1" }
}

extension Tag {
    @Tag static var knownBug: Self
}
