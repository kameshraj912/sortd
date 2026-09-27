import SwiftUI
import SwiftData

/// "Which card ends in 1234?" on Home (spec 2026-09-27): a receipt or bank
/// alert's last 4 matched none of Raj's cards, and there are two or more to
/// choose from (one active card settles it on its own, no prompt —
/// `CardBook.noteUnmatchedDigits`). Same card style as `ActivationCard` /
/// `FinishSetupCard`. Sits after the Activation card, never on top of it.
struct WhichCardCard: View {
    @State private var queue: [String] = PendingCardDigits.load()
    @State private var picked = 0
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let cards = Card.mine
        Group {
            if let last4 = queue.first,
               CardDigitsPrompt.shouldShow(queue: queue, activeCardCount: cards.count,
                                           duringSetup: TipState.setupShowing, duringIntro: TipState.introShowing) {
                content(last4: last4, cards: cards)
            }
        }
        // A sync while Home was in the background, or another instance of
        // this same card (Settings › Cards), can change the queue.
        .onChange(of: scenePhase) { _, phase in if phase == .active { queue = PendingCardDigits.load() } }
    }

    private func content(last4: String, cards: [Card]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Which card ends in \(last4)?")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A receipt came in for a card Sortd doesn't know yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            FlowLayout(spacing: 8) {
                ForEach(cards) { card in
                    Button { pick(card, last4: last4) } label: {
                        Text(card.name).chip(selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Not one of mine") { notMine(last4) }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
        .setupCard()
        .task(id: last4) { Analytics.shared.track(.cardDigitsPrompted) }
        .feedback(.select, trigger: picked)
        .transition(.opacity)
    }

    /// Raj picked a card: save the digits on it and move over every
    /// purchase that carried them, then drop the digits from the queue.
    private func pick(_ card: Card, last4: String) {
        CardBook.shared.assign(last4, to: card)
        reassignPurchases(carrying: last4, to: card)
        queue = PendingCardDigits.clear(last4)
        picked += 1
        Analytics.shared.track(.cardDigitsAnswered, ["choice": .string("card")])
    }

    /// "Not one of mine": just forget the digits. The purchases they were on
    /// stay as they are.
    private func notMine(_ last4: String) {
        queue = PendingCardDigits.clear(last4)
        picked += 1
        Analytics.shared.track(.cardDigitsAnswered, ["choice": .string("not_mine")])
    }

    private func reassignPurchases(carrying last4: String, to card: Card) {
        guard let matches = try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.unmatchedLast4 == last4 })) else { return }
        for t in matches {
            t.card = card
            t.unmatchedLast4 = nil
        }
        try? context.save()
    }
}
