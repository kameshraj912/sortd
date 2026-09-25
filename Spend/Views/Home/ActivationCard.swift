import SwiftUI

/// The aha card on Home (overhaul sub-spec 6): the first purchase Sortd
/// logged by itself has landed. One line and a tick, celebrating the
/// logging and never the amount, then the app's single notification ask.
/// Stays until the ask is answered; "Not now" means it never comes back.
struct ActivationCard: View {
    @AppStorage(Activation.seenKey) private var seen = false
    @AppStorage(Activation.askedKey) private var asked = false
    @AppStorage(Activation.celebratedKey) private var celebrated = false
    @AppStorage(SetupProfile.checkInKey) private var checkInRaw = SetupProfile.CheckIn.sunday.rawValue
    /// Apple's alert is up: one tap is enough.
    @State private var asking = false

    /// The check-in saved during setup, or the Sunday default when the
    /// answer was "only when it matters" (nothing to schedule for that).
    private var choice: SetupProfile.CheckIn {
        let saved = SetupProfile.CheckIn(rawValue: checkInRaw) ?? .sunday
        return saved.time == nil ? .sunday : saved
    }

    private var askLine: String {
        switch choice {
        case .morning: "Want a check-in each morning?"
        case .evening: "Want a check-in each evening?"
        case .sunday, .needed: "Want a Sunday recap?"
        }
    }

    var body: some View {
        // Follows the tap-through setup: the old flow (DEBUG escape) asked
        // about notifications itself, so it never shows this.
        if SetupFlow.usesNewFlow, seen, !asked {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.up)
                        .symbolEffect(.bounce, value: celebrated)
                    Text("Logged by itself. That's Sortd working.")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Logged by itself. That's Sortd working.")

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text(askLine).font(.body)
                    Text(choice.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 10) {
                    Button { turnOn() } label: {
                        Text("Yes")
                            .font(.headline)
                            .foregroundStyle(Color.onBrand)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.brand)
                    Button { decline() } label: {
                        Text("Not now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .disabled(asking)
            }
            .setupCard()
            .onAppear { if !celebrated { celebrated = true } }
            // The one `.aha` haptic in the app: once, the first time the
            // card is seen.
            .feedback(.aha, trigger: celebrated)
            .transition(.opacity)
        }
    }

    /// Yes: Apple's own alert, then the check-in is scheduled if allowed.
    /// Either way the ask is over.
    private func turnOn() {
        guard !asking else { return }
        asking = true
        Task {
            let choice = choice
            let allowed = await Reminders.turnOnCheckIn(choice)
            // Keep the saved answer in step with what will actually come:
            // denied means none, as Settings and the old setup say.
            checkInRaw = (allowed ? choice : .needed).rawValue
            asking = false
            withAnimation(.snappy) { Activation.markNotificationAsked() }
        }
    }

    /// No: never asked again (research 03 §9). Settings can still turn it on.
    private func decline() {
        withAnimation(.snappy) { Activation.markNotificationAsked() }
    }
}
