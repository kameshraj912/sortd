import SwiftUI
import PhotosUI
import VisionKit

/// "Scan Receipt" sheet: take a photo of a paper receipt (or pick one) and
/// read it on the phone. Hands back what it found; the New Purchase sheet
/// fills in the fields and the user checks them before saving.
/// Images are read in memory and never saved.
struct ReceiptScanView: View {
    let onRead: (ReceiptReading) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var problem: String?

    private var cameraWorks: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View { screenBody.analyticsScreen(.receiptScan) }

    @ViewBuilder private var screenBody: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Scan a receipt")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.ink)
                    Text("Sortd reads the shop, total, date and card on this iPhone. The photo isn't saved or sent.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if reading {
                    ProgressView("Reading your receipt…")
                        .frame(maxWidth: .infinity, minHeight: ButtonMetrics.height)
                } else {
                    VStack(spacing: 10) {
                        if cameraWorks {
                            Button { showingCamera = true } label: {
                                Label("Use Camera", systemImage: "camera")
                                    .primaryPill()
                            }
                            .primaryGlass()
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Choose Photo", systemImage: "photo")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: ButtonMetrics.height)
                                .foregroundStyle(Color.ink)
                                .surface(radius: 26)
                        }
                        .buttonStyle(.pressable)
                    }
                }

                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .background(Color.page)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentCamera { pages in
                    showingCamera = false
                    guard !pages.isEmpty else { return }
                    read(pages)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.page)
    }

    private func load(_ item: PhotosPickerItem) async {
        reading = true
        problem = nil
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let page = ReceiptScanner.Page(image) else {
            reading = false
            problem = "Couldn't open that photo. Try another one."
            return
        }
        read([page])
    }

    private func read(_ pages: [ReceiptScanner.Page]) {
        reading = true
        problem = nil
        Task {
            let text = await ReceiptScanner.recognizeText(in: pages)
            let result = await ReceiptScanner.read(text: text)
            reading = false
            let success = !(text.isEmpty || result.isEmpty)
            Analytics.shared.track(.receiptScanned, ["success": .bool(success)])
            if !success {
                problem = "Couldn't read this receipt. Try again in better light, or type it in."
                return
            }
            if result.amount == nil {
                // Still useful (shop, date), but say so.
                log.info("Receipt scan found no total")
            }
            onRead(result)
            dismiss()
        }
    }
}

extension ReceiptScanner.Page {
    /// A page from a photo or scan, keeping which way is up.
    init?(_ image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        let orientation: CGImagePropertyOrientation = switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
        self.init(image: cg, orientation: orientation)
    }
}

/// VisionKit's document camera: finds the paper edges, flattens the page
/// and hands back one image per page (empty if cancelled).
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([ReceiptScanner.Page]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([ReceiptScanner.Page]) -> Void
        init(onFinish: @escaping ([ReceiptScanner.Page]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { ReceiptScanner.Page(scan.imageOfPage(at: $0)) }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            log.error("Document camera failed: \(error.localizedDescription)")
            onFinish([])
        }
    }
}
