import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Spend

/// Bug hunt 26 Sep 2026: App Lock. (The same hunt's Gmail sender-check cases
/// went with the Gmail feature on 2 Oct 2026.)
@MainActor
struct BugHuntAppLockTests {

    // MARK: - App Lock

    private func fresh() -> AppLock {
        // `AppLock()` reads the switch from UserDefaults; start unlocked,
        // and clear any stored "require after" choice so the default
        // (immediately) applies, regardless of what a real device has saved.
        UserDefaults.standard.set(false, forKey: AppLock.enabledKey)
        UserDefaults.standard.removeObject(forKey: AppLock.requireAfterKey)
        return AppLock()
    }

    /// App Lock never locks again after the first unlock: coming back from
    /// the background goes background → inactive → active, and the
    /// `.inactive` step sets `lastActive = now`, so `.active` sees no time away.
    @Test
    func appLockLocksAgainAfterTenMinutesAway() {
        let lock = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Leaving the app: active → inactive → background.
        lock.sceneChanged(to: .inactive, enabled: true, onboarded: true, now: t0)
        lock.sceneChanged(to: .background, enabled: true, onboarded: true, now: t0)
        // Ten minutes later, coming back: background → inactive → active.
        let back = t0.addingTimeInterval(600)
        lock.sceneChanged(to: .inactive, enabled: true, onboarded: true, now: back)
        lock.sceneChanged(to: .active, enabled: true, onboarded: true, now: back)
        #expect(lock.isLocked, "ten minutes away with App Lock on must lock")
    }

    /// Control: without the `.inactive` step the same trip does lock, which
    /// pins the cause to that step and not to `shouldLock`.
    @Test func appLockLocksWhenActiveFollowsBackgroundDirectly() {
        let lock = fresh()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        lock.sceneChanged(to: .background, enabled: true, onboarded: true, now: t0)
        lock.sceneChanged(to: .active, enabled: true, onboarded: true, now: t0.addingTimeInterval(600))
        #expect(lock.isLocked)
    }
}
