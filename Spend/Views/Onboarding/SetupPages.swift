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

// MARK: - Shared style
//
// One look for every setup screen, using Apple's text styles so Dynamic
// Type works: titles .title bold, body text .body, secondary .subheadline,
// small labels .footnote (never smaller). Icons are plain one-colour SF
// Symbols, the same as Settings; colour stays for spending categories.

/// The one icon style: plain, ink-coloured, fixed width so text lines up.
struct RowIcon: View {
    let symbol: String
    /// Grows with the text, so a big icon never touches the title (finding 15).
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 28
    init(_ symbol: String) { self.symbol = symbol }

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.ink)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The one card surface on setup screens.
    func setupCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// One answer: a solid card with a symbol (glass is for controls, not
/// content). A check circle for pick-any questions, a dot for pick-one.
struct OptionCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let symbol: String
    let title: String
    var detail: String? = nil
    let selected: Bool
    var multi = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // At the largest text sizes the words need the room.
                if !typeSize.isAccessibilitySize { RowIcon(symbol) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Color.ink)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? (multi ? "checkmark.circle.fill" : "largecircle.fill.circle") : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.ink : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Color.ink : .clear, lineWidth: 1.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .feedback(.select, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Title, the brand bar, a subtitle, and "Question 2 of 5" above it all.
struct SetupHeader: View {
    var counter: String? = nil
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let counter {
                Text(counter)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(title).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            BrandBar(width: 14, height: 3)
            if let subtitle {
                Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }
}

// MARK: - Copy

/// The line under each screen's title. The tap-through flow (sub-spec 6)
/// says one warm, plain line per screen (the heyclicky reference: talk,
/// don't announce); the old lines stay until the flag goes. Titles are
/// the same in both.
enum SetupCopy {
    static func line(_ step: SetupFlow.Step) -> String? {
        SetupFlow.usesNewFlow ? new[step] : old[step]
    }

    /// The currency step once a currency other than the phone's is picked
    /// (the default line would then be untrue). Nil in the old flow.
    static var currencyPicked: String? {
        SetupFlow.usesNewFlow ? "Totals will show in this one. Change it any time." : nil
    }

    /// The email step. With iCloud backup in the build, receipts can leave
    /// the phone, for the person's own iCloud only: say so.
    private static let emailLine: String = {
        #if SORTD_ICLOUD
        "It stays on your phone, and in your iCloud if you turn backup on."
        #else
        "Read on your iPhone. Nothing leaves it."
        #endif
    }()

    private static let old: [SetupFlow.Step: String] = [
        .welcome: "Your spending, logged by itself.",
        .goals: "Pick any.",
        .feeling: "No wrong answer.",
        .budget: "Change it any time.",
        .checkIn: "One short notification. Change it any time.",
        .plan: "Built from your answers. Change any of it in Settings.",
        .cards: "Tap each bank you pay with. Two cards at one bank? Tap twice.",
        .cardDetails: "So receipts land on the right card. Only the last 4.",
        .applePay: "Three steps, about a minute.",
        .email: "From receipts and bank alerts in your Gmail.",
    ]

    private static let new: [SetupFlow.Step: String] = [
        .welcome: "Hi. Let's get your spending to log itself.",
        .goals: "Tap any that fit. Not sure? Just continue.",
        .payment: "So the right things get set up first.",
        .currency: "We picked the one your iPhone uses.",
        .feeling: "No wrong answer. It just sets the tone.",
        .budget: "Leave it empty if you're not sure yet.",
        .checkIn: "One short note. We'll ask about notifications later, not now.",
        .plan: "All set from your answers. The rest can wait.",
        .cards: "Tap each bank you pay with. Fine to skip for now.",
        .cardDetails: "So receipts find the right card. Fine to skip today.",
        .applePay: "About a minute, once. Or do it later from Home.",
        .email: emailLine,
    ]
}

// MARK: - Questions

struct GoalsPage: View {
    let counter: String
    @Binding var goals: Set<SetupProfile.Goal>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "What should Sortd help with?",
                        subtitle: SetupCopy.line(.goals))
            VStack(spacing: 10) {
                ForEach(SetupProfile.Goal.allCases) { goal in
                    OptionCard(symbol: goal.symbol, title: goal.title, selected: goals.contains(goal), multi: true) {
                        withAnimation(.snappy) {
                            if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                        }
                    }
                }
            }
        }
    }
}

struct PaymentPage: View {
    let counter: String
    @Binding var payment: SetupProfile.Payment?
    /// Pick-one: moves on by itself a moment after a tap.
    var onPicked: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "How do you usually pay?", subtitle: SetupCopy.line(.payment))
            VStack(spacing: 10) {
                ForEach(SetupProfile.Payment.allCases) { p in
                    OptionCard(symbol: p.symbol, title: p.title, selected: payment == p) {
                        withAnimation(.snappy) { payment = p }
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            onPicked()
                        }
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
            SetupHeader(counter: counter, title: "How does your spending feel lately?",
                        subtitle: SetupCopy.line(.feeling))
            VStack(spacing: 10) {
                ForEach(SetupProfile.Feeling.allCases) { f in
                    OptionCard(symbol: f.symbol, title: f.title, selected: feeling == f) {
                        withAnimation(.snappy) { feeling = f }
                    }
                }
            }
            if let feeling {
                HStack(alignment: .top, spacing: 12) {
                    RowIcon("heart")
                    Text(feeling.reply).font(.body).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .setupCard()
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
    /// The bill-reminder toggle needs a permission the new flow doesn't ask
    /// for during setup, so that flow leaves it out.
    var showBills = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(counter: counter, title: "When should we check in?",
                        subtitle: SetupCopy.line(.checkIn))
            VStack(spacing: 10) {
                ForEach(SetupProfile.CheckIn.allCases) { c in
                    OptionCard(symbol: c.symbol, title: c.title, detail: c.detail, selected: checkIn == c) {
                        withAnimation(.snappy) { checkIn = c }
                    }
                }
            }
            if showBills { billsToggle }
        }
    }

    private var billsToggle: some View {
        Toggle(isOn: $billReminders) {
            HStack(spacing: 12) {
                RowIcon("bell")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me the day before a bill").font(.body)
                    Text("9 am, the day before it's charged")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .tint(Color.brand)
        .setupCard()
        .padding(.top, 16)
    }
}

// MARK: - Building

/// A short pause that shows back what the answers did. Tap to skip.
struct BuildingPage: View {
    let lines: [String]
    let done: () -> Void
    @State private var shown = 0
    /// VoiceOver users move on themselves; the timer would cut them off.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 60)
            Text(shown == lines.count ? "Your Sortd is ready" : "Building your Sortd")
                .font(.title.weight(.bold))
                .contentTransition(.opacity)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: i < shown ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.title3)
                            .foregroundStyle(i < shown ? Color.up : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(line)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(i < shown ? Color.ink : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .setupCard(padding: 20)
            if voiceOver {
                Button("Continue", action: done)
                    .buttonStyle(.glassProminent)
                    .tint(Color.brand)
                    .controlSize(.large)
            }
            Spacer(minLength: 60)
        }
        .contentShape(.rect)
        .onTapGesture(perform: done)
        .feedback(.confirm, trigger: shown == lines.count)
        .task {
            if voiceOver {
                shown = lines.count
                return
            }
            for i in 1...lines.count {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.snappy) { shown = i }
            }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { done() }
        }
        .accessibilityElement(children: voiceOver ? .contain : .combine)
        .accessibilityAddTraits(voiceOver ? [] : .isButton)
        .accessibilityHint(voiceOver ? "" : "Tap to continue")
    }
}

// MARK: - Plan

/// "Here's your Sortd": their settings in one card, then what's left, in
/// the order that matters to this person. The list starts one step in.
struct PlanPage: View {
    let summary: String
    let tasks: [SetupTask]
    let settings: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeader(title: "Here's your Sortd", subtitle: summary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(settings, id: \.1) { symbol, text in
                    HStack(spacing: 12) {
                        RowIcon(symbol)
                        Text(text).font(.body)
                    }
                }
            }
            .setupCard()

            HStack(alignment: .firstTextBaseline) {
                Text("Finish Setup").font(.headline)
                Spacer()
                Text("\(SetupChecklist.doneCount(tasks)) of \(tasks.count) done")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            SetupChecklistList(tasks: tasks)

            HStack(alignment: .top, spacing: 12) {
                RowIcon("lock.iphone")
                Text("Everything stays on this iPhone. Sortd never asks for your bank login.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
        }
    }
}

/// The checklist rows, as a card. Tapping a row is optional: the plan screen
/// shows it, Home makes each row open its step.
struct SetupChecklistList: View {
    let tasks: [SetupTask]
    var open: ((SetupTask.Kind) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                if i > 0 { Divider().padding(.leading, 56) }
                // Rows only become buttons where they open something (Home),
                // so the plan screen's list isn't greyed out as "disabled".
                if let open, !task.done {
                    Button { open(task.kind) } label: { row(task) }
                        .buttonStyle(.plain)
                } else {
                    row(task)
                }
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func row(_ task: SetupTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.done ? Color.up : Color.secondary.opacity(0.5))
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body)
                    .foregroundStyle(task.done ? Color.secondary : Color.ink)
                    .strikethrough(task.done && task.kind != .answers, color: .secondary)
                Text(task.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if open != nil, !task.done {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.done ? "Done" : "Not done")
    }
}
