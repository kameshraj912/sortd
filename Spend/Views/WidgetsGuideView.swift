import SwiftUI

/// What Sortd puts on the Home and Lock Screen, and how to change it.
///
/// Widgets are easy to miss — they live in a long-press menu most people
/// never open — so this says plainly what's there and how to get it. It
/// doesn't draw fake widgets: Apple's guidance is not to mirror a widget's
/// appearance inside the app, because something that looks like a widget
/// but doesn't behave like one is confusing.
struct WidgetsGuideView: View {
    var body: some View {
        List {
            ListPageTitle(title: "Widgets")

            Section {
                widget("chart.bar.xaxis", "Spending",
                       "What you've spent against what you have to spend, in your category colours.")
                widget("circle.dashed", "Budget Ring",
                       "How much of this month's budget is left, as a ring. Turns red when you go over.")
                widget("sun.max", "Today",
                       "What you've spent today, and the last thing you paid for.")
                widget("list.bullet", "Recent",
                       "Your last three purchases. Tap one to open it.")
                widget("plus.circle", "Quick Add",
                       "Add a purchase, scan a receipt or import a statement in one tap.")
                widget("calendar.badge.clock", "Bills",
                       "Subscriptions and bills about to charge, with the day each one is due.")
                widget("lock", "Lock Screen",
                       "Today's total as a small dial, a line under the clock, or plain text.")
            }

            Section {
                step(1, "Touch and hold an empty part of your Home Screen until the icons wobble.")
                step(2, "Tap Edit at the top left, then Add Widget.")
                step(3, "Search for Sortd and pick the one you want.")
            } header: {
                BoldHeader("How to Add")
            }

            Section {
                row("circle.lefthalf.filled", "Light, dark or automatic",
                    "Touch and hold a widget, tap Edit Widget, then pick a Look. Automatic follows your iPhone.")
                row("calendar", "Today, this week or this month",
                    "The Spending widget can show any of the three. Same place: Edit Widget, then Show.")
            } header: {
                BoldHeader("Options")
            }

            Section {
                Text("Widgets read a small summary on this iPhone — today's total, what's left, your last few purchases, the next few bills. Nothing is uploaded. Shop names and amounts are hidden while the iPhone is locked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                BoldHeader("Privacy")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Widgets")
    }

    private func widget(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(Color.ink)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        widget(symbol, title, detail)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 22, height: 22)
                .background(Color.brand, in: .circle)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}
