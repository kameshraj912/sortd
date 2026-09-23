import Foundation
import PDFKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

/// Turns a file or a photo into the text `StatementImport` reads.
///
/// CSV is read as text. A PDF gives up its own text when it has any; a
/// scanned one is rendered and read with Vision, the same on-device
/// recogniser the receipt camera uses. A screenshot is read the same way.
///
/// Everything happens on this iPhone. The file is read once and never
/// copied into Sortd's storage.
nonisolated enum StatementReader {

    enum Failure: LocalizedError {
        case unreadable
        case noPermission
        case empty
        case tooBig(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable: "Sortd couldn't read that file."
            case .noPermission: "Sortd couldn't open that file. Try saving it to Files first, then pick it from there."
            case .empty: "That file has no text in it."
            case .tooBig(let mb): "That file is \(mb) MB. Try a single statement rather than a year of them."
            }
        }
    }

    /// Statements are small. A 50 MB "statement" is a mistake, and reading
    /// it would hang the phone.
    static let sizeLimit = 25 * 1024 * 1024

    struct Reading {
        var text: String
        /// True when the text came from OCR, so the user is told to check it.
        var wasScanned: Bool
    }

    // MARK: - Files

    static func read(fileAt url: URL) async throws -> Reading {
        // A file from the document picker lives outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > sizeLimit { throw Failure.tooBig(size / 1024 / 1024) }

        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return try await readPDF(at: url)
        }
        if type?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Failure.unreadable
            }
            let text = await ReceiptScanner.recognizeText(in: [.init(image: image, orientation: orientation(of: source))])
            guard !text.isEmpty else { throw Failure.empty }
            return Reading(text: text, wasScanned: true)
        }

        // CSV, TSV, TXT, OFX/QIF exports — all just text.
        guard let data = try? Data(contentsOf: url) else { throw Failure.noPermission }
        guard let text = decodeText(data) else { throw Failure.unreadable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        return Reading(text: text, wasScanned: false)
    }

    /// Banks export in whatever encoding they feel like. UTF-8 first, then
    /// the usual Windows fallback, so pounds and accents don't turn to mush.
    static func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return nil
    }

    // MARK: - PDF

    /// How little text a PDF page can have before we treat it as a scan.
    private static let scannedThreshold = 40

    static func readPDF(at url: URL) async throws -> Reading {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        if document.isLocked { throw Failure.noPermission }

        var text = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if let s = page.string { text += s + "\n" }
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= scannedThreshold {
            return Reading(text: text, wasScanned: false)
        }

        // A scan. Render each page and read it with Vision.
        var pages: [ReceiptScanner.Page] = []
        for i in 0..<min(document.pageCount, 20) {
            guard let page = document.page(at: i), let image = render(page) else { continue }
            pages.append(.init(image: image, orientation: .up))
        }
        guard !pages.isEmpty else { throw Failure.empty }
        let scanned = await ReceiptScanner.recognizeText(in: pages)
        guard !scanned.isEmpty else { throw Failure.empty }
        return Reading(text: scanned, wasScanned: true)
    }

    /// Renders a PDF page at roughly 200 dpi — enough for Vision to read
    /// statement rows without making a 100 MB bitmap.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(200.0 / 72.0, 4000 / max(bounds.width, bounds.height))
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? UInt32,
              let value = CGImagePropertyOrientation(rawValue: raw) else { return .up }
        return value
    }

    // MARK: - What kind of file is this?

    /// A Sortd backup and a bank statement both arrive through the same
    /// picker, so the file says which it is rather than the user.
    static func looksLikeBackup(_ text: String) -> Bool {
        text.contains("\"format\"") && text.contains(Backup.formatName)
    }

    /// File types the picker offers. Deliberately wide: people have their
    /// statements in all of these.
    static var readableTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf, .image]
        if let backup = UTType(filenameExtension: "sortdbackup") { types.append(backup) }
        types.append(.json)
        return types
    }
}
