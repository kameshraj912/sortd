import SwiftUI
import StoreKit

/// Settings › About › Leave a tip. Three tips at the App Store's own
/// prices, and a plain thank-you after one. Nothing in the app changes.
struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var jar = TipJar.shared
    /// The product being bought right now, so its row shows a spinner.
    @State private var buying: String?
    @State private var thanked = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Sortd is free, and every feature stays free. If it helps you, you can leave a tip. A tip unlocks nothing; it just says thanks.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }

                if thanked {
                    Section {
                        Label("Thank you.", systemImage: "heart.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.up)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }

                Section {
                    if jar.products.isEmpty {
                        loadingRow
                    } else {
                        ForEach(jar.products, id: \.id) { product in
                            tipRow(product)
                        }
                    }
                } footer: {
                    if let message {
                        Text(message)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Leave a Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { if jar.products.isEmpty { await jar.load() } }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            if jar.loadError == nil { ProgressView() }
            Text(jar.loadError ?? "Loading tips…").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if jar.loadError != nil {
                Button("Try Again") { Task { await jar.load() } }.font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await tip(product) }
        } label: {
            HStack {
                Text(product.displayName).foregroundStyle(Color.ink)
                Spacer()
                if buying == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Color.ink)
                }
            }
            .contentShape(.rect)
        }
        .disabled(buying != nil)
        .accessibilityLabel("\(product.displayName), \(Money.spoken(product.price, product.priceFormatStyle.currencyCode))")
    }

    private func tip(_ product: Product) async {
        buying = product.id
        message = nil
        defer { buying = nil }
        switch await jar.tip(product) {
        case .thanked: withAnimation(.snappy) { thanked = true }
        case .cancelled: break
        case .failed(let error): message = error.localizedDescription
        }
    }
}
