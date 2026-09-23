import SwiftUI

/// Vertical list of steps joined by a line, like Wise's transfer updates.
struct Timeline: View {
    struct Step: Identifiable {
        enum State { case done, current, upcoming }
        let id = UUID()
        let title: String
        let detail: String
        let state: State
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        marker(step.state)
                            .frame(width: 22, height: 22)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.weight(step.state == .current ? .bold : .semibold))
                            .foregroundStyle(step.state == .upcoming ? .secondary : .primary)
                        Text(step.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, index < steps.count - 1 ? 16 : 0)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.state == .current ? "In progress" : step.state == .done ? "Done" : "Not yet")
            }
        }
    }

    @ViewBuilder
    private func marker(_ state: Step.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        case .current:
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
        case .upcoming:
            Circle()
                .strokeBorder(Color(.systemGray3), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }
}
