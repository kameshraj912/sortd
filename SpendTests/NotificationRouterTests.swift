import Testing
import Foundation
@testable import Spend

/// `NotificationRouter.deliver`: a notification tap arrives on a background thread,
/// but the link opens and the system's completion handler runs on the main thread.
/// Calling that handler off main crashed build 1.0 (4) (Sentry SORTD-2).
struct NotificationRouterTests {
    private final class Seen: @unchecked Sendable {
        var opened: [URL] = []
        var completedOnMain: Bool?
    }

    private func deliverFromBackground(_ raw: String?) async -> Seen {
        let seen = Seen()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                NotificationRouter.deliver(raw, completion: {
                    seen.completedOnMain = Thread.isMainThread
                    done.resume()
                }, open: { url in
                    seen.opened.append(url)
                })
            }
        }
        return seen
    }

    @Test func completionRunsOnMainThread() async {
        let seen = await deliverFromBackground("sortd://activity")
        #expect(seen.completedOnMain == true)
        #expect(seen.opened == [URL(string: "sortd://activity")!])
    }

    @Test func noLinkStillCompletes() async {
        let seen = await deliverFromBackground(nil)
        #expect(seen.completedOnMain == true)
        #expect(seen.opened.isEmpty)
    }
}
