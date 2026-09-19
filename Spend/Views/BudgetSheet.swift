import SwiftUI

/// Monzo-style: one big centred number you can edit, quick preset chips,
/// a solid Save pill and an outlined Remove.
struct BudgetSheet: View {
    @Binding var budget: Double
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = 0
    @FocusState private var focused: Bool

    private static let presets: [Double] = [500, 800, 1000, 1500, 2000]

    private var value: Double {
        (AmountParser.parse(text)?.amount.double) ?? 0
    }

    private var range: String {
        let month = Calendar.current.dateInterval(of: .month, for: .now)
        let start = (month?.start ?? .now).formatted(.dateTime.day().month(.abbreviated))
        let end = (month?.end.addingTimeInterval(-1) ?? .now).formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end) · all cards"
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Text("Monthly Budget")
                    .font(.headline)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $text)
                        .font(.largeTitle.weight(.bold))
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .fixedSize()
                        .accessibilityLabel("Monthly budget in Australian dollars")
                    Image(systemName: "pencil")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .onTapGesture { focused = true }
                Text(range)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Quick presets, like the gift-budget chips.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        let selected = value == preset
                        Button {
                            text = String(Int(preset))
                        } label: {
                            Text(Money.format(Decimal(preset), Money.home, cents: false))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .chip(selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    budget = value
                    saved += 1
                    dismiss()
                } label: {
                    Text("Save")
                        .primaryPill(enabled: value > 0)
                }
                .disabled(value <= 0)

                if budget > 0 {
                    Button {
                        budget = 0
                        dismiss()
                    } label: {
                        Text("Remove Budget")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.primary)
                            .overlay(Capsule().strokeBorder(Color.primary, lineWidth: 1.5))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .onAppear {
            if budget > 0 { text = String(Int(budget)) }
        }
        .sensoryFeedback(.success, trigger: saved)
        .presentationDetents([.medium, .large])
        // Solid, so the cards behind don't bleed through the glass.
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}
