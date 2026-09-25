import SwiftUI
import StoreKit

/// Settings › About › Leave a tip. Three tips at the App Store's own
/// prices, and a plain thank-you after one. Nothing in the app changes.
struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var jar = TipJar.shared
    /// The product being bought right now, so its row shows a spinner.
    @State private var buying: String?
    @State private var thanked = false
    @State private var message: String?
    /// A Try Again in flight, so the row shows a spinner.
    @State private var retrying = false

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
                            .onAppear { AccessibilityNotification.Announcement("Thank you").post() }
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

    /// A spinner while loading (including a retry, held long enough to
    /// be seen: with no App Store the load fails at once, so a tap on Try
    /// Again used to change nothing on screen), then a plain line when
    /// nothing came back.
    private var loadingRow: some View {
        HStack(spacing: 10) {
            if loading {
                ProgressView()
                Text("Loading tips…").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Tips need the App Store. Try again later.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Try Again") { Task { await retry() } }.font(.subheadline.weight(.semibold))
            }
        }
        .animation(.snappy, value: loading)
    }

    private var loading: Bool { retrying || jar.loadError == nil }

    private func retry() async {
        retrying = true
        defer { retrying = false }
        await jar.load()
        // Keep the spinner up for a moment so the tap visibly did something.
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await tip(product) }
        } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    // Name over price at accessibility sizes, so neither is
                    // squeezed beside the other.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName).foregroundStyle(Color.ink)
                        if buying == product.id { ProgressView() } else { price(product) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Text(product.displayName).foregroundStyle(Color.ink)
                        Spacer()
                        if buying == product.id { ProgressView() } else { price(product) }
                    }
                }
            }
            .contentShape(.rect)
        }
        .disabled(buying != nil)
        .accessibilityLabel("\(product.displayName), \(Money.spoken(product.price, product.priceFormatStyle.currencyCode))")
    }

    private func price(_ product: Product) -> some View {
        Text(product.displayPrice)
            .font(.body.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Color.ink)
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
