import SwiftUI

// The question and plan screens of setup. The flow itself (order, progress,
// buttons) lives in `OnboardingView`; these only draw a page and write to the
// bindings they're given.

/// A soft glow of the four brand colours behind the hero screens, so the
/// glass buttons above it have something to bend.
struct SetupAura: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t / 3) * 0.08)
            let c = Float(cos(t / 4) * 0.08)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + s, 0.45 + c], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color.brandPalette[0], Color.brandPalette[1], Color.brandPalette[2],
                    Color.brandPalette[3], Color.page, Color.brandPalette[0],
                    Color.page, Color.page, Color.page,
                ])
        }
        .opacity(scheme == .dark ? 0.35 : 0.28)
        .blur(radius: 40)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// One answer: a solid card with a symbol (glass is for controls, not
/// content). A check circle for pick-any questions, a dot for pick-one.
struct OptionCard: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let selected: Bool
    var multi = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? Color.onBrand : Color.ink)
                    .frame(width: 38, height: 38)
                    .background(selected ? Color.brand : Color.track, in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? (multi ? "checkmark.circle.fill" : "largecircle.fill.circle") : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.ink : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.ink : .clear, lineWidth: 1.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Title, the brand bar, a subtitle, and "Question 2 of 5" above it all.
struct SetupHeader: View {
    var counter: String? = nil
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let counter {
                Text(counter)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            BrandBar(width: 14, height: 3)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }
}

// MARK: - Questions

struct GoalsPage: View {
    let counter: String
    @Binding var goals: Set<SetupProfile.Goal>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "What do you want Sortd to help with?",
                        subtitle: "Pick any. It decides what Sortd shows you first.")
            VStack(spacing: 10) {
                ForEach(SetupProfile.Goal.allCases) { goal in
                    OptionCard(symbol: goal.symbol, title: goal.title, selected: goals.contains(goal), multi: true) {
                        withAnimation(.snappy) {
                            if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                        }
                    }
                }
            }
            Text("Not sure yet? Just tap Continue.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }
}

struct PaymentPage: View {
    let counter: String
    @Binding var payment: SetupProfile.Payment?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "How do you usually pay?",
                        subtitle: "So Sortd sets up the way you actually spend.")
            VStack(spacing: 10) {
                ForEach(SetupProfile.Payment.allCases) { p in
                    OptionCard(symbol: p.symbol, title: p.title, selected: payment == p) {
                        withAnimation(.snappy) { payment = p }
                    }
                }
            }
        }
    }
}

struct FeelingPage: View {
    let counter: String
    @Binding var feeling: SetupProfile.Feeling?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "How do you feel about your spending lately?",
                        subtitle: "There's no wrong answer. It changes how Sortd talks to you.")
            VStack(spacing: 10) {
                ForEach(SetupProfile.Feeling.allCases) { f in
                    OptionCard(symbol: f.symbol, title: f.title, selected: feeling == f) {
                        withAnimation(.snappy) { feeling = f }
                    }
                }
            }
            if let feeling {
                Label(feeling.reply, systemImage: "heart")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(feeling)
            }
        }
    }
}

struct CheckInPage: View {
    let counter: String
    @Binding var checkIn: SetupProfile.CheckIn
    @Binding var billReminders: Bool
    let isPro: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "When do you want a quick look?",
                        subtitle: "One short notification at the time you pick. Change it any time.")
            VStack(spacing: 10) {
                ForEach(SetupProfile.CheckIn.allCases) { c in
                    OptionCard(symbol: c.symbol, title: c.title, detail: c.detail, selected: checkIn == c) {
                        withAnimation(.snappy) { checkIn = c }
                    }
                }
            }
            Toggle(isOn: $billReminders) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tell me the day before a bill is due").font(.subheadline.weight(.medium))
                    Text(isPro ? "Subscriptions and bills, 9 am the day before." : "Part of Pro · included in the free trial")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(Color.brand)
            .padding(14)
            .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
            .padding(.top, 16)
        }
    }
}

// MARK: - Building

/// A short pause that shows back what the answers did. Tap to skip.
struct BuildingPage: View {
    let lines: [String]
    let done: () -> Void
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 60)
            Text("Building your Sortd")
                .font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: i < shown ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.title3)
                            .foregroundStyle(i < shown ? Color.up : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(line)
                            .font(.body)
                            .foregroundStyle(i < shown ? Color.ink : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Spacer(minLength: 60)
        }
        .contentShape(.rect)
        .onTapGesture(perform: done)
        .sensoryFeedback(.impact(weight: .light), trigger: shown)
        .task {
            for i in 1...lines.count {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.snappy) { shown = i }
            }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { done() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to continue")
    }
}

// MARK: - Plan

struct PlanItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let time: String
    let pro: Bool
}

/// "Here's your Sortd": what the answers set up, and the few steps left,
/// in the order that matters to this person.
struct PlanPage: View {
    let summary: String
    let items: [PlanItem]
    let settings: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(title: "Here's your Sortd", subtitle: summary)

            // What's already set, as small glass chips over the glow.
            FlowLayout(spacing: 8) {
                ForEach(settings, id: \.0) { symbol, text in
                    Label(text, systemImage: symbol)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .padding(.bottom, 20)

            Text("A few steps left")
                .font(.headline)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 60) }
                    HStack(spacing: 14) {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.onBrand)
                            .frame(width: 28, height: 28)
                            .background(Color.ink, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.time).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(item.pro ? "Pro" : "Free")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.pro ? Color.onBrand : Color.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.pro ? Color.brand : Color.track, in: .capsule)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))

            Label("Everything stays on this iPhone. Sortd never asks for your bank login.", systemImage: "lock.iphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
    }
}
