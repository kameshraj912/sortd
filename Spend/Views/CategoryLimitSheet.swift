import SwiftUI
import Combine

/// Set, change or remove one category's monthly limit. Same look as
/// BudgetSheet: a big editable number, quick chips, Save and Remove.
struct CategoryLimitSheet: View {
    let category: SpendCategory
    /// Told the new limit (nil when removed) the instant Save or Remove
    /// runs, so the screen that opened this sheet can show it right away
    /// instead of waiting on a `UserDefaults.didChangeNotification` that
    /// fires for every setting in the app, not just this one.
    var onChange: (Double?) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var current: Double = 0
    @State private var text = ""
    @State private var saved = 0
    @FocusState private var focused: Bool

    private static let presets: [Double] = [50, 100, 200, 300, 500]

    private var value: Double {
        (AmountParser.parse(text)?.amount.double) ?? 0
    }

    /// What Save does: parse what's typed, persist it, and hand back the
    /// exact value that just went into the store. Reading `value` back out
    /// of `CategoryBudgets` here (instead of only computing it from `text`)
    /// means the caller's copy can never drift from what was actually saved.
    static func apply(_ text: String, to category: SpendCategory, _ defaults: UserDefaults = .standard) -> Double? {
        let value = (AmountParser.parse(text)?.amount.double) ?? 0
        CategoryBudgets.set(value, for: category, defaults)
        return CategoryBudgets.limit(for: category, defaults)
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Text("\(category.name) Limit")
                    .font(.headline)
                    .lineLimit(1)
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
                    Text(Money.symbol(Money.home))
                        .font(.title.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $text)
                        .font(.money)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .fixedSize()
                        .accessibilityLabel("Monthly limit for \(category.name) in \(Money.home)")
                    Image(systemName: "pencil")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .onTapGesture { focused = true }
                Text("Each month · all cards")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        let selected = value == preset
                        Button {
                            text = String(Int(preset))
                        } label: {
                            Text(Money.format(Decimal(preset), Money.home, cents: false))
                                .chip(selected: selected)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    onChange(Self.apply(text, to: category))
                    saved += 1
                    Analytics.shared.track(.categoryLimitSet, ["category": .string(category.rawValue)])
                    dismiss()
                } label: {
                    Text("Save")
                        .primaryPill(enabled: value > 0)
                }
                .primaryGlass()
                .disabled(value <= 0)

                if current > 0 {
                    Button {
                        CategoryBudgets.remove(category)
                        onChange(nil)
                        dismiss()
                    } label: {
                        Text("Remove Limit")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.primary)
                            .overlay(Capsule().strokeBorder(Color.primary, lineWidth: 1.5))
                    }
                }
            }
            .buttonStyle(.pressable)
        }
        .padding(20)
        .onAppear {
            current = CategoryBudgets.limit(for: category) ?? 0
            if current > 0 { text = String(Int(current)) }
        }
        .toolbar {
            // The number pad has no Return key; without this there is
            // no way to put it away and reach Save underneath.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }.fontWeight(.semibold)
            }
        }
        .feedback(.confirm, trigger: saved)
        .presentationDetents([.height(420), .large])
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}

extension CategoryBudgets.Status {
    /// Bar colour: the category's own until 80%, then amber, then red.
    func color(_ category: SpendCategory) -> Color {
        switch self {
        case .ok: category.color
        case .near: Color.brandPalette[1]
        case .over: Color.down
        }
    }
}

extension View {
    /// Re-runs `action` when the category limits change anywhere in the app.
    func onCategoryLimitsChange(_ action: @escaping () -> Void) -> some View {
        onAppear(perform: action)
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in action() }
    }
}
