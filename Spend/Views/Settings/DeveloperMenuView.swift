import SwiftUI

/// Settings › About, tap the version line 7 times within 3 seconds: a
/// hidden sheet so Raj can watch an event, a Sentry report and a crash
/// arrive without waiting for the real thing. Not gated behind a build
/// flag — it works in Release too, since it is already hidden behind the
/// taps.
struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sentEvent = 0
    @State private var sentReport = 0
    @State private var confirmingCrash = false
    @State private var recentErrors = ErrorLog.recent()

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Send Test Event") {
                        Analytics.shared.track(.developerTestEvent,
                                               ["sent_at": .string(ISO8601DateFormatter().string(from: .now))])
                        sentEvent += 1
                    }
                    Button("Send Test Report to Sentry") {
                        CrashReporting.sendTestReport()
                        sentReport += 1
                    }
                    Button("Crash Now", role: .destructive) {
                        confirmingCrash = true
                    }
                } header: {
                    BoldHeader("Try It")
                } footer: {
                    Text("The test report needs Sentry's DSN and sharing turned on. Crashing closes Sortd immediately; the next launch sends it, if sharing is on.")
                }

                Section {
                    LabeledContent("Analytics", value: Analytics.shared.isEnabled ? "On" : "Off")
                    LabeledContent("Session Replay", value: Analytics.shared.isEnabled && Analytics.replayBuildFlagOn ? "On" : "Off")
                    LabeledContent("PostHog Host", value: Analytics.postHogHost)
                    LabeledContent("Sentry", value: CrashReporting.isOn ? "On" : "Off")
                    LabeledContent("Version", value: "\(version) (\(build))")
                    LabeledContent("User ID") {
                        Text(Analytics.shared.identityHash ?? "—")
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } header: {
                    BoldHeader("Status")
                }

                // Apple Pay tap pipeline (spec 2026-09-26, failsafe #12): what
                // last arrived, what's waiting on a retry, what the last retry did.
                Section {
                    LabeledContent("Last tap received", value: lastTapReceivedText)
                    // Every field as it arrived, tap fields and Wallet's
                    // notification both, and which trigger ran.
                    if let raw = UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) {
                        Text(raw)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Queued taps", value: "\(TapQueue.count)")
                    LabeledContent("Last replay", value: TapQueue.lastReplaySummary)
                } header: {
                    BoldHeader("Apple Pay Tap Queue")
                }

                // The last 10 raw lines, newest first: a tap and its Wallet
                // notification seconds apart both stay visible.
                Section {
                    let runs = LogPurchaseIntent.recentRuns()
                    if runs.isEmpty {
                        Text("None yet").foregroundStyle(.secondary)
                    }
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    BoldHeader("Recent Runs")
                }

                Section {
                    if recentErrors.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recentErrors.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.place): \(item.type)")
                                    .font(.footnote.weight(.semibold))
                                if !item.message.isEmpty {
                                    Text(item.message)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.date.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Button("Clear", role: .destructive) {
                            ErrorLog.clear()
                            recentErrors = []
                        }
                    }
                } header: {
                    BoldHeader("Recent Errors")
                } footer: {
                    Text("The last 20 failures on this phone. Only the error type and place reach Sentry, never this text.")
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .feedback(.confirm, trigger: sentEvent)
            .feedback(.confirm, trigger: sentReport)
            .alert("Crash the app?", isPresented: $confirmingCrash) {
                Button("Crash", role: .destructive) {
                    fatalError("Developer menu: forced crash (Settings › About)")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sortd will close right away.")
            }
        }
    }

    private var lastTapReceivedText: String {
        guard let date = LogPurchaseIntent.lastTapReceivedAt else { return "Never" }
        let raw = UserDefaults.standard.string(forKey: LogPurchaseIntent.lastTapKey) ?? ""
        let kind = raw.contains("notification run") ? " · notification" : raw.contains("tap run") ? " · tap" : ""
        return date.formatted(date: .abbreviated, time: .standard) + kind
    }
}
