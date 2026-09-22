import SwiftUI
import SwiftData

/// A slow job as one calm block: a spinner (or a bar once the amount of
/// work is known), one line of plain words, and a way forward when it stops.
struct SyncProgressCard: View {
    let status: SyncStatus
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SyncStatusIcon(status: status)
                Text(status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let fraction = status.fraction {
                ProgressView(value: fraction)
                    .tint(Color.brand)
                    .accessibilityHidden(true)
            }
            if case .adding(_, _, let added) = status.phase, added > 0 {
                Text("\(added) added so far")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if case .failed(let failure) = status.phase {
                Button(failure.retryTitle, action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(Color.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 16)
        .accessibilityElement(children: .contain)
        .animation(.snappy, value: status.phase)
    }
}

/// Spinner while working, a tick when done, a warning when stopped.
struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        Group {
            switch status.phase {
            case .finished:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.down)
            case .adding:
                Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(Color.ink)
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}

/// Home's small line about Gmail, so a connect or sync that is still going
/// (or that stopped) is visible after leaving the Connect screen.
struct GmailStatusBanner: View {
    @Environment(\.modelContext) private var context
    private let status = SyncStatus.gmail
    /// The tab bar keeps its size at every text size, so this does too.
    private let bottomClearance: CGFloat = 55

    var body: some View {
        Group {
            if status.showsOnHome {
                HStack(spacing: 12) {
                    SyncStatusIcon(status: status)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let fraction = status.fraction {
                            ProgressView(value: fraction).tint(Color.brand).accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 4)
                    if case .failed(let failure) = status.phase {
                        Button(failure.retryTitle) { GmailSync.retry(failure, in: context) }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(Color.ink)
                    }
                    if !status.isBusy {
                        Button("Dismiss", systemImage: "xmark") { status.dismiss() }
                            .labelStyle(.iconOnly)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, status.isBusy ? 14 : 4)
                .padding(.vertical, status.isBusy ? 12 : 2)
                .background(Color.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.horizontal, 20)
                // Clear of the app's flat tab bar (49 pt + 6 pt top padding),
                // which sits over the tabs rather than shrinking their safe area.
                .padding(.bottom, 8 + bottomClearance)
                .accessibilityElement(children: .contain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: status.showsOnHome)
    }
}

extension GmailSync {
    /// Try Again: sign in again when access ended, otherwise sync again.
    @MainActor
    static func retry(_ failure: SyncFailure, in context: ModelContext) {
        if failure.needsSignIn || accounts.isEmpty { startConnect(in: context) } else { startSync(in: context) }
    }
}
