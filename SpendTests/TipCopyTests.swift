import Testing
import Foundation
@testable import Spend

/// The six tip lines, kept plain and short: no "Pro", one sentence, no
/// trailing period on the title, unique snake_case ids for Analytics to key
/// on later. Contract lives in docs/specs/2026-09-25-free-app-overhaul-7-tips.md.
struct TipCopyTests {

    @Test func hasExactlySixTips() {
        #expect(TipCopy.all.count == 6)
    }

    @Test func idsAreUniqueSnakeCase() {
        let ids = TipCopy.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(id == id.lowercased(), "\(id)")
            #expect(!id.contains(" "), "\(id)")
            #expect(!id.isEmpty)
        }
    }

    @Test func titlesHaveNoTrailingPeriod() {
        for tip in TipCopy.all {
            #expect(!tip.title.hasSuffix("."), "\(tip.id): \(tip.title)")
        }
    }

    @Test func noLineMentionsPro() {
        for tip in TipCopy.all {
            #expect(!tip.title.localizedCaseInsensitiveContains("pro"), "\(tip.id) title")
            #expect(!tip.message.localizedCaseInsensitiveContains("pro"), "\(tip.id) message")
        }
    }

    @Test func messagesAreOnePlainLineUnderEightyCharacters() {
        for tip in TipCopy.all {
            #expect(!tip.message.contains("\n"), "\(tip.id)")
            #expect(tip.message.count < 80, "\(tip.id): \(tip.message.count) chars")
        }
    }

    @Test func titlesAreOnePlainLineUnderEightyCharacters() {
        for tip in TipCopy.all {
            #expect(!tip.title.contains("\n"), "\(tip.id)")
            #expect(tip.title.count < 80, "\(tip.id): \(tip.title.count) chars")
        }
    }
}
