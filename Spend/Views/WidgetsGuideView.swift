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
            ListPageTitle(title: "Widgets",
                          subtitle: "Your spending on the Home and Lock Screen.")

            Section {
                widget("chart.bar.xaxis", "Spending",
                       "What you've spent today against what a day is worth, with the month in your category colours.")
                widget("plus.circle", "Quick Add",
                       "Add a purchase, scan a receipt or open Import — one tap, without finding the app first.")
                widget("calendar.badge.clock", "Bills",
                       "Subscriptions and bills about to charge, with a countdown.")
                widget("lock", "Lock Screen",
                       "Today's total as a small dial, a line under the clock, or plain text.")
            } header: {
                BoldHeader("What There Is")
            }

            Section {
                step(1, "Touch and hold an empty part of your Home Screen until the icons wobble.")
                step(2, "Tap the button at the top left, then Add Widget.")
                step(3, "Search for Sortd and pick the one you want.")
            } header: {
                BoldHeader("Adding One")
            }

            Section {
                row("circle.lefthalf.filled", "Light, dark or automatic",
                    "Touch and hold a Sortd widget, tap Edit Widget, then pick a Look. Automatic follows your iPhone; Light and Dark stay put whatever the phone does.")
                row("calendar", "Today, this week or this month",
                    "The Spending widget can show any of the three. Same place: Edit Widget, then Show.")
            } header: {
                BoldHeader("Changing It")
            }

            Section {
                Text("Widgets read a small summary Sortd writes on this iPhone — today's total, what's left, and the next few bills. Nothing is uploaded, and the widget never opens your purchases.")
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
