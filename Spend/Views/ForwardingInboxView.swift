import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

/// Settings › Forwarding Inbox: a private address to forward receipts to,
/// instead of connecting Gmail. Not linked from Settings yet (see
/// `ForwardingInbox` for the one line that does it).
struct ForwardingInboxView: View {
    @Environment(\.modelContext) private var context
    @State private var inbox = ForwardingInbox.shared
    @State private var error: String?
    @State private var copied = false
    @State private var confirmingNew = false
    @State private var confirmingOff = false

    var body: some View {
        Form {
            if let address = inbox.address, inbox.isOn {
                onSections(address)
            } else {
                offSection
            }
        }
        .navigationTitle("Forwarding Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .task { if inbox.isOn { await check(force: false) } }
    }

    // MARK: Off

    private var offSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Forward receipts to Sortd", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                Text("Get a private email address. Set Gmail or Outlook to forward receipts and bank alerts to it, and Sortd reads them on this iPhone.")
                Text("No Google sign-in. Our server only ever holds your emails encrypted so only this iPhone can open them, and deletes each one once it's here, or after 24 hours.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                Task { await run { try await inbox.turnOn() } }
            } label: {
                HStack {
                    Text("Get My Address")
                    Spacer()
                    if inbox.busy { ProgressView() }
                }
            }
            .disabled(inbox.busy)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } footer: {
            Text("Setting up forwarding needs Gmail or Outlook on a computer, once.")
        }
    }

    // MARK: On

    @ViewBuilder
    private func onSections(_ address: String) -> some View {
        if let request = inbox.gmailRequest { gmailRequestSection(request) }

        Section {
            Text(address)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .accessibilityLabel("Your Sortd address: \(address)")
            Button {
                UIPasteboard.general.string = address
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: address) { Label("Share Address", systemImage: "square.and.arrow.up") }
        } header: {
            BoldHeader("Your Address")
        } footer: {
            Text("Keep it to yourself. Anyone with it can send email to Sortd.")
        }

        if let url = inbox.setupURL {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: url.absoluteString)
                        .frame(width: 120, height: 120)
                        .accessibilityLabel("QR code for the setup page")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan with your computer's camera, or open:")
                        Text("inbox.sortd.page/setup").font(.footnote.monospaced())
                        Text("It makes a Gmail filter that forwards only receipts and bank alerts.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                ShareLink(item: url) { Label("Send the Setup Link to Your Computer", systemImage: "laptopcomputer.and.arrow.down") }
            } header: {
                BoldHeader("Set Up on Your Computer")
            } footer: {
                Text("Gmail filters can only be made on a computer, not in the Gmail app.")
            }
        }

        Section {
            DisclosureGroup("Gmail") {
                Steps([
                    "Gmail › Settings › See all settings › Forwarding and POP/IMAP › Add a forwarding address. Paste your address.",
                    "Come back here and tap Confirm when Google's request appears.",
                    "Leave \"Forward a copy of incoming mail\" off. The filter sends only receipts.",
                    "Settings › Filters and Blocked Addresses › Import filters, with the file from the setup page.",
                ])
            }
            DisclosureGroup("Outlook.com") {
                Steps([
                    "Outlook on the web › Settings › Mail › Rules › Add new rule.",
                    "Condition: Subject includes receipt, invoice, order confirmation, transaction alert.",
                    "Action: Redirect to your Sortd address. Save.",
                ])
            }
        } header: {
            BoldHeader("Steps")
        }

        Section {
            Button {
                Task { await check(force: true) }
            } label: {
                HStack {
                    Text("Check Now")
                    Spacer()
                    if inbox.busy { ProgressView() }
                }
            }
            .disabled(inbox.busy)
            if let result = inbox.lastResult {
                Text(result).font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } footer: {
            Text("Sortd checks each time you open it. Forwarded emails wait on the server for up to 24 hours.")
        }

        Section {
            Button("New Address") { confirmingNew = true }
            Button("Turn Off", role: .destructive) { confirmingOff = true }
        } footer: {
            Text("A new address stops the old one working. Update the forwarding address in Gmail or Outlook after.")
        }
        .confirmationDialog("Get a new address?", isPresented: $confirmingNew, titleVisibility: .visible) {
            Button("New Address") { Task { await run { try await inbox.newAddress() } } }
        } message: {
            Text("Mail sent to \(address) will bounce from now on.")
        }
        .confirmationDialog("Turn off the forwarding inbox?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn Off") { Task { await inbox.turnOff(deletePurchases: false, in: context) } }
            Button("Turn Off and Delete Its Purchases", role: .destructive) {
                Task { await inbox.turnOff(deletePurchases: true, in: context) }
            }
        } message: {
            Text("The address and anything waiting for this iPhone are deleted from Sortd's server.")
        }
    }

    private func gmailRequestSection(_ r: GmailForwardingRequest) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Gmail wants to forward here", systemImage: "envelope.badge.fill").font(.headline)
                if let who = r.requestedBy { Text("From \(who). Only confirm if that's you.") }
            }
            .padding(.vertical, 4)
            if let url = r.url {
                Link(destination: url) { Label("Confirm in Gmail", systemImage: "checkmark.seal") }
            }
            if let code = r.code {
                HStack {
                    Text("Code")
                    Spacer()
                    Text(code).font(.body.monospaced()).textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
            Button("Done") { inbox.dismissGmailRequest() }
        } header: {
            BoldHeader("Confirm Forwarding")
        } footer: {
            Text("Confirm opens Google's page. Or type the code into Gmail's forwarding settings and click Verify.")
        }
    }

    // MARK: Actions

    private func check(force: Bool) async {
        error = nil
        if force {
            do { try await inbox.sync(in: context) } catch { self.error = error.localizedDescription }
        } else {
            await inbox.syncIfOn(in: context)
        }
    }

    private func run(_ work: () async throws -> String) async {
        error = nil
        copied = false
        do { _ = try await work() } catch { self.error = error.localizedDescription }
    }
}

/// Numbered steps in a disclosure group.
private struct Steps: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { i, step in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                Text(step)
            }
            .font(.subheadline)
        }
    }
}

/// A QR code drawn with Core Image, crisp at any size.
private struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }

    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    NavigationStack { ForwardingInboxView() }
        .modelContainer(for: [Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self], inMemory: true)
}
