import Testing
import Foundation
@testable import Spend

/// `sortd://purchase/<id>`: the Recent widget's rows open that purchase.
/// Parsing is a pure function, so it is tested without a screen; the screen
/// that opens the detail reads `Router.pendingPurchase`.
@MainActor
struct RouterPurchaseLinkTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func aPurchaseLinkCarriesItsId() {
        let id = UUID()
        let target = Router.target(for: url("sortd://purchase/\(id.uuidString)"))
        #expect(target == Router.Target(name: "purchase", id: id.uuidString))
    }

    @Test func existingLinksStillParseWithNoId() {
        for name in ["add", "scan", "budget", "activity", "insights", "bills", "import", "home"] {
            #expect(Router.target(for: url("sortd://\(name)")) == Router.Target(name: name, id: nil))
        }
    }

    @Test func aTrailingSlashIsNotAnId() {
        #expect(Router.target(for: url("sortd://purchase/"))?.id == nil)
        #expect(Router.target(for: url("sortd://activity/"))?.id == nil)
    }

    @Test func otherSchemesAreIgnored() {
        #expect(Router.target(for: url("https://purchase/abc")) == nil)
    }

    @Test func followingAPurchaseLinkGoesToActivityAndRemembersWhichOne() {
        let router = Router.shared
        router.tab = .home
        router.pendingPurchase = nil
        let id = UUID()
        router.follow(Router.target(for: url("sortd://purchase/\(id.uuidString)"))!)
        #expect(router.tab == .activity)
        #expect(router.pendingPurchase == id)
        router.pendingPurchase = nil
        router.tab = .home
    }

    @Test func aBrokenIdStillLandsOnActivityWithNothingPending() {
        let router = Router.shared
        router.tab = .home
        router.pendingPurchase = nil
        router.follow(Router.target(for: url("sortd://purchase/not-a-uuid"))!)
        #expect(router.tab == .activity)
        #expect(router.pendingPurchase == nil)
        router.tab = .home
    }

    @Test func aPurchaseLinkWithNoIdLandsOnActivity() {
        let router = Router.shared
        router.tab = .home
        router.pendingPurchase = nil
        router.follow(Router.target(for: url("sortd://purchase"))!)
        #expect(router.tab == .activity)
        #expect(router.pendingPurchase == nil)
        router.tab = .home
    }

    @Test func otherLinksLeaveAnyPendingPurchaseAlone() {
        let router = Router.shared
        router.pendingPurchase = nil
        router.follow(Router.target(for: url("sortd://insights"))!)
        #expect(router.tab == .insights)
        #expect(router.pendingPurchase == nil)
        router.tab = .home
    }
}
