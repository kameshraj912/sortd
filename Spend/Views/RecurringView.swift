import SwiftUI
import SwiftData

/// Subscriptions and bills found in Raj's history: what they cost a month,
/// what's due next, and anything that needs a look (price rises, charges
/// after cancelling, charges in another country's currency).
struct RecurringView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    /// Bumped after a change to Raj's choices so the list recomputes.
    @State private var revision = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let all = { _ = revision; return transactions.recurring() }()
        let active = all.filter { $0.status == .active }
        let soon = active.filter { $0.nextDate <= Calendar.current.date(byAdding: .day, value: 30, to: .now)! }
        let alerts = all.filter { needsLook($0) }
        let stopped = all.filter { $0.status != .active }

        List {
            ListPageTitle(title: "Recurring", subtitle: "Subscriptions and bills, predicted from your payments.")
            if !all.isEmpty {
                Section {
                    summary(active)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            // Price rises and charges after cancelling get a row each; payments
            // still billing in another country's currency are grouped into one.
            let single = alerts.filter { $0.chargedAfterCancel || ($0.priceChange ?? 0) > 0 }
            let away = alerts.filter { !single.contains($0) }
            if !single.isEmpty || !away.isEmpty {
                Section(bold: "Needs a Look") {
                    ForEach(single) { r in alertRow(r) }
                    if !away.isEmpty { awayRow(away) }
                }
            }

            if !soon.isEmpty {
                Section {
                    ForEach(soon) { r in row(r, showNext: true) }
                } header: {
                    BoldHeader("Next 30 Days")
                } footer: {
                    Text("Predicted from your past payments. Amounts are the last charge.")
                }
            }

            let subs = active.filter(\.isSubscription)
            let bills = active.filter { !$0.isSubscription }
            if !subs.isEmpty {
                Section(bold: "Subscriptions") {
                    ForEach(subs) { r in row(r, showNext: false) }
                }
            }
            if !bills.isEmpty {
                Section(bold: "Bills & Rent") {
                    ForEach(bills) { r in row(r, showNext: false) }
                }
            }

            if !stopped.isEmpty {
                Section {
                    ForEach(stopped) { r in row(r, showNext: false).opacity(0.6) }
                } header: {
                    BoldHeader("Stopped")
                } footer: {
                    Text("Cancelled by you, or no payment when one was due.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Recurring")
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No Recurring Payments Yet", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Subscriptions and bills show up here after they've charged twice, or once with an App Store receipt. \(SortdVoice.noRecurring)"))
            }
        }
    }

    // MARK: Pieces

    /// Subscriptions lead (the part you can actually cut); rent and bills
    /// are shown beside them, not mixed in.
    private func summary(_ active: [Recurring]) -> some View {
        let subs = active.filter(\.isSubscription).reduce(0) { $0 + $1.monthlyAUD }
        let bills = active.filter { !$0.isSubscription }.reduce(0) { $0 + $1.monthlyAUD }
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(Money.format(Decimal(subs), Money.home, cents: false))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("a month on subscriptions · \(Money.format(Decimal(subs * 12), Money.home, cents: false)) a year")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if bills > 0 {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                    Label("Bills & rent", systemImage: "house")
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text("\(Money.format(Decimal(bills), Money.home, cents: false)) a month").monospacedDigit()
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .surface(radius: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func row(_ r: Recurring, showNext: Bool) -> some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
            CategoryIcon(category: r.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.merchant).lineLimit(1)
                Text(showNext ? Self.when(r.nextDate) : "\(r.cadence.name) · \(r.card.shortLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(r.amount, r.currency)).monospacedDigit()
                if showNext {
                    Text(r.cadence.name).font(.caption).foregroundStyle(.secondary)
                } else if r.status == .active {
                    Text("next \(Self.shortDate(r.nextDate))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            if r.status == .cancelled {
                Button("Undo") { RecurringPrefs.undoCancel(r.key); revision += 1 }
            } else {
                Button("Cancelled") { RecurringPrefs.markCancelled(r.key); revision += 1 }
                    .tint(.orange)
                Button("Not Recurring") { RecurringPrefs.ignore(r.key); revision += 1 }
                    .tint(.gray)
            }
        }
        .contextMenu {
            Button("I Cancelled This", systemImage: "xmark.circle") { RecurringPrefs.markCancelled(r.key); revision += 1 }
            Button("Not a Recurring Payment", systemImage: "eye.slash") { RecurringPrefs.ignore(r.key); revision += 1 }
        }
    }

    private func alertRow(_ r: Recurring) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: r.chargedAfterCancel ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.chargedAfterCancel ? Color.down : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.merchant).font(.body.weight(.semibold))
                Text(alertText(r)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func awayRow(_ list: [Recurring]) -> some View {
        let currencies = Set(list.map(\.currency)).sorted().joined(separator: ", ")
        let names = list.map(\.merchant).joined(separator: ", ")
        let monthly = list.reduce(0) { $0 + $1.monthlyAUD }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe").foregroundStyle(Color.orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(list.count) still billing in \(currencies)").font(.body.weight(.semibold))
                Text("\(names). About \(Money.format(Decimal(monthly), Money.home, cents: false)) a month. Still need them where you are now?")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func needsLook(_ r: Recurring) -> Bool {
        r.chargedAfterCancel || (r.status == .active && ((r.priceChange ?? 0) > 0 || isAway(r)))
    }

    /// Charged in a currency that isn't where Raj is now (e.g. an SGD plan
    /// still billing while he's in Melbourne).
    private func isAway(_ r: Recurring) -> Bool {
        // Only a currency that's neither home nor where you are now. USD is
        // how most apps and online services bill everyone, so it's normal.
        r.currency != Money.home && r.currency != LocalCurrency.current() && r.currency != "USD"
    }

    private func alertText(_ r: Recurring) -> String {
        if r.chargedAfterCancel {
            return "Charged \(Money.format(r.amount, r.currency)) on \(r.lastDate.formatted(.dateTime.day().month())) after you marked it cancelled."
        }
        if let change = r.priceChange, change > 0, let old = r.previousAmount {
            return "Went up from \(Money.format(old, r.currency)) to \(Money.format(r.amount, r.currency))."
        }
        return "Still charging in \(r.currency) while you're using \(LocalCurrency.current()). Still need it?"
    }

    /// "7 Oct", or "15 Sep 2027" when it isn't this year.
    static func shortDate(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        return "In \(days) days · \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }
}

/// Home: the next few payments, like a bill calendar.
struct UpcomingSection: View {
    let recurring: [Recurring]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let soon = Array(recurring.filter { $0.status == .active && $0.nextDate <= Calendar.current.date(byAdding: .day, value: 14, to: .now)! }.prefix(3))
        if !soon.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    ProGate(feature: .recurring) { RecurringView() }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Coming up").font(.title3.weight(.bold)).foregroundStyle(Color.ink)
                        Spacer()
                        Text("See all").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            .accessibilityLabel("See all, coming up")
                    }
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    ForEach(soon) { r in
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
                            CategoryIcon(category: r.category, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.merchant).lineLimit(1)
                                Text(RecurringView.when(r.nextDate)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(r.amount, r.currency)).monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
                .surface()
            }
        }
    }
}
