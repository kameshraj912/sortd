import Testing
import UIKit
@testable import Spend

/// Asset rename guard (overhaul sub-spec 9).
///
/// Two catalog images are looked up by string, so a rename in
/// `Assets.xcassets` would not fail the build; it would show a blank at
/// runtime. `Spend-Info.plist` points the launch screen at "LaunchWordmark",
/// and the welcome, lock and wallet-guide views use `Image("BrandIcon")`.
/// The tests run inside the app (TEST_HOST), so `Bundle.main` is Sortd.app.
struct BrandAssetsTests {
    @Test(arguments: ["BrandIcon", "LaunchWordmark"])
    func brandImageExistsInTheAppBundle(name: String) {
        #expect(UIImage(named: name) != nil, "\(name) is missing from Assets.xcassets")
    }
}
