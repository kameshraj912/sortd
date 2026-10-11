import Testing
import CoreGraphics
@testable import Spend

/// Home's "Your Cards" carousel (bug, 11 Oct 2026): the last card could not
/// reach the leading edge, so the dots and "Where It Went · <card>" stayed
/// on the card before it. The trailing margin gives it room to.
@Suite("CardCarouselMargin")
struct CardCarouselMarginTests {
    /// Scroll view widths: iPhone SE, 17/18 Pro, Pro Max, each less Home's 40pt padding.
    let widths: [CGFloat] = [335, 362, 400]

    /// Can the last of `pages` cards scroll to the leading edge?
    func lastPageReachesLeading(pages: Int, container: CGFloat, accessibility: Bool) -> Bool {
        let card = HomeView.cardWidth(container, accessibility: accessibility)
        let gap = HomeView.cardSpacing
        let margin = HomeView.cardTrailingMargin(container: container, card: card)
        let content = CGFloat(pages) * card + CGFloat(pages - 1) * gap + margin
        let maxOffset = max(0, content - container)
        let lastLeading = CGFloat(pages - 1) * (card + gap)
        return maxOffset + 0.5 >= lastLeading
    }

    @Test func defaultSizeMarginIsTheRestOfTheRow() {
        for w in widths {
            let card = HomeView.cardWidth(w)
            #expect(HomeView.cardTrailingMargin(container: w, card: card) == w - card)
        }
        // 362pt: card 195.48, so 166.52 after it.
        #expect(abs(HomeView.cardTrailingMargin(container: 362, card: HomeView.cardWidth(362)) - 166.52) < 0.01)
    }

    @Test func accessibilityMarginIsTheRestOfTheRow() {
        for w in widths {
            let card = HomeView.cardWidth(w, accessibility: true)
            #expect(HomeView.cardTrailingMargin(container: w, card: card) == w - card)
        }
        // 400pt: the card caps at 344, leaving 56.
        #expect(HomeView.cardTrailingMargin(container: 400, card: HomeView.cardWidth(400, accessibility: true)) == 56)
    }

    @Test func leadingInsetComesOffTheMargin() {
        #expect(HomeView.cardTrailingMargin(container: 362, card: 200, inset: 20) == 142)
    }

    @Test func oneCardLastPageReachesLeading() {
        // "All cards" plus one card.
        for w in widths {
            #expect(lastPageReachesLeading(pages: 2, container: w, accessibility: false))
            #expect(lastPageReachesLeading(pages: 2, container: w, accessibility: true))
        }
    }

    @Test func fiveCardsLastPageReachesLeading() {
        for w in widths {
            #expect(lastPageReachesLeading(pages: 6, container: w, accessibility: false))
            #expect(lastPageReachesLeading(pages: 6, container: w, accessibility: true))
        }
    }

    @Test func withoutTheMarginTheLastCardWasStuck() {
        // The bug: three pages, no margin, last card short of the leading edge.
        let w: CGFloat = 362, card = HomeView.cardWidth(w), gap = HomeView.cardSpacing
        let maxOffset = 3 * card + 2 * gap - w
        #expect(maxOffset < 2 * (card + gap))
    }

    @Test func marginIsNeverNegative() {
        #expect(HomeView.cardTrailingMargin(container: 0, card: 0) == 0)
        #expect(HomeView.cardTrailingMargin(container: 200, card: 300) == 0)
        #expect(HomeView.cardTrailingMargin(container: 300, card: 290, inset: 40) == 0)
        for w in stride(from: CGFloat(0), through: 1400, by: 25) {
            for ax in [false, true] {
                #expect(HomeView.cardTrailingMargin(container: w, card: HomeView.cardWidth(w, accessibility: ax)) >= 0)
            }
        }
    }
}
