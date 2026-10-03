import Foundation
import CoreGraphics
import ImageIO
import Vision

/// What Sortd could read off a paper receipt. Every field is optional:
/// the New Purchase sheet only fills in what was found, and the user checks
/// it before saving.
nonisolated struct ReceiptReading: Equatable, Sendable {
    var merchant: String?
    /// Digits with two decimals, e.g. "42.50".
    var amount: String?
    /// Three-letter code, e.g. "AUD".
    var currency: String?
    var last4: String?
    var date: Date?

    var isEmpty: Bool { merchant == nil && amount == nil && last4 == nil && date == nil }
}

/// Reads receipts from the camera or a photo.
///
/// 1. `recognizeText` runs Vision's on-device text recognition.
/// 2. `read(text:)` asks Apple's on-device model when it's available (the
///    amount must still appear in the text), and fills gaps with the rules.
/// 3. The rules (`extract`, `total`, `merchant`, `date`) are pure, so they
///    are unit-tested.
///
/// Nothing leaves the phone and the images are not kept.
nonisolated enum ReceiptScanner {

    // MARK: OCR

    /// One page to read: the image and which way is up.
    struct Page: @unchecked Sendable {
        let image: CGImage
        let orientation: CGImagePropertyOrientation
    }

    /// Text on the pages, one receipt line per line, top to bottom.
    @concurrent
    static func recognizeText(in pages: [Page]) async -> String {
        var out: [String] = []
        for page in pages {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: page.image, orientation: page.orientation)
            do {
                try handler.perform([request])
            } catch {
                continue
            }
            let pieces = (request.results ?? []).compactMap { obs -> Piece? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                return Piece(text: text, box: obs.boundingBox)
            }
            out += lines(from: pieces)
        }
        return out.joined(separator: "\n")
    }

    /// A bit of text Vision found, with its box (0–1, origin bottom-left).
    struct Piece: Sendable {
        let text: String
        let box: CGRect
    }

    /// Joins pieces on the same row, left to right, so "TOTAL" and "$12.50"
    /// at opposite edges of the paper become one line "TOTAL $12.50".
    static func lines(from pieces: [Piece]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Piece]] = []
        for p in sorted {
            if let last = rows.last?.last,
               abs(last.box.midY - p.box.midY) < max(min(last.box.height, p.box.height) * 0.5, 0.004) {
                rows[rows.count - 1].append(p)
            } else {
                rows.append([p])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    // MARK: Reading

    /// Best reading of receipt text: the on-device model when it can run,
    /// with the rules filling anything it left out. The date always comes
    /// from the rules.
    @MainActor
    static func read(text: String, now: Date = .now) async -> ReceiptReading {
        var result = extract(from: text, now: now)
        if ReceiptAI.isAvailable, let ai = await ReceiptAI.read(text: text) {
            result.amount = ai.amount ?? result.amount
            result.currency = ai.amount != nil ? (ai.currency ?? result.currency) : result.currency
            result.merchant = ai.merchant ?? result.merchant
            result.last4 = ai.last4 ?? result.last4
        }
        return result
    }

    /// Rule-based reading, used when Apple Intelligence isn't available.
    static func extract(from text: String, now: Date = .now) -> ReceiptReading {
        let found = total(in: text)
        return ReceiptReading(
            merchant: merchant(in: text),
            amount: found?.amount,
            currency: found?.currency,
            last4: GenericReceipts.last4(in: text),
            date: date(in: text, now: now))
    }

    /// The total paid. Uses `GenericReceipts.total`, but first drops lines that only
    /// mention tax, change or rounding ("GST included in total $1.14"),
    /// which would otherwise win as the last "total".
    /// Falls back to a "TOTAL 12.50" line with no currency sign, in the
    /// user's home currency.
    static func total(in text: String) -> (currency: String, amount: String)? {
        let lines = text.components(separatedBy: .newlines)
        // A cash receipt that gives change: "AMOUNT PAID $50.00" is the note
        // handed over, not the total. (On a card slip, with no change, it is.)
        let givesChange = lines.contains { line in
            let l = line.lowercased().trimmingCharacters(in: .whitespaces)
            return l.hasPrefix("change") && l.range(of: "[1-9]", options: .regularExpression) != nil
        }
        let tendered = ["amount paid", "amount tendered", "tendered", "paid", "cash"]
        let kept = lines.filter { line in
            let l = line.lowercased().trimmingCharacters(in: .whitespaces)
            if givesChange, tendered.contains(where: { l.hasPrefix($0) }) { return false }
            let startsAsTotal = ["total", "grand total", "amount", "eftpos", "card"].contains { l.hasPrefix($0) }
                && !l.hasPrefix("total gst") && !l.hasPrefix("total tax")
            let noise = ["gst", "tax", "vat", "change", "rounding", "cash", "savings", "you saved", "discount"]
            return startsAsTotal || !noise.contains { l.contains($0) }
        }.joined(separator: "\n")

        if let found = GenericReceipts.total(in: kept) { return found }

        // "TOTAL 12.50" / "TOTAL: 1,204.30" with no currency sign. A signed
        // SUBTOTAL above it no longer wins: the labels are whole words.
        let pattern = GenericReceipts.notInsideWord
            + #"(?:grand total|total due|amount due|total)\s*[:\-–]?\s*(\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = kept as NSString
        guard let m = regex.matches(in: kept, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        let value = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
        guard let d = Decimal(string: value), d > 0 else { return nil }
        return (Money.home, value)
    }

    /// The shop name: usually the first real line at the top of the receipt.
    /// Skips "Tax Invoice", ABN/phone/address lines, dates and amounts.
    static func merchant(in text: String) -> String? {
        let skip = ["tax invoice", "invoice", "receipt", "abn", "gst", "welcome", "thank", "www", "http", "@", ".com",
                    "tel", "phone", "ph:", "order", "table", "date", "time", "cashier", "server", "store", "copy",
                    "merchant", "terminal", "eftpos", "street", " st ", " rd ", " ave "]
        for raw in text.components(separatedBy: .newlines).prefix(8) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "*-=#:")))
            let lower = " " + line.lowercased() + " "
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            guard letters >= 3, digits <= 2, letters * 2 > line.count,
                  !skip.contains(where: { lower.contains($0) }) else { continue }
            // "WOOLWORTHS METRO" → "Woolworths Metro"; leave "McDonald's" alone.
            let name = line == line.uppercased() ? line.capitalized : line
            return String(name.prefix(40))
        }
        return nil
    }

    // MARK: Dates

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    /// The purchase date if the receipt shows one: "19/09/2026", "19-09-26",
    /// "19 Sep 2026", "Sep 19, 2026", "2026-09-19". Day comes before month
    /// (Australia, Singapore). Dates in the future or over two years old
    /// are ignored. Noon that day, unless it's today (then `now`).
    static func date(in text: String, now: Date = .now) -> Date? {
        let mon = #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"#
        // (pattern, index of day, month, year groups)
        let patterns: [(String, Int, Int, Int)] = [
            (#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#, 3, 2, 1),
            (#"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b"#, 1, 2, 3),
            (#"\b(\d{1,2})(?:st|nd|rd|th)?[ \-]"# + mon + #"[ \-,]*(\d{4}|\d{2})\b"#, 1, 2, 3),
            (mon + #" (\d{1,2})(?:st|nd|rd|th)?,? (\d{4})\b"#, 2, 1, 3),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for (pattern, di, mi, yi) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let dayText = ns.substring(with: m.range(at: di))
                let monthText = ns.substring(with: m.range(at: mi)).lowercased()
                let yearText = ns.substring(with: m.range(at: yi))
                guard let day = Int(dayText),
                      let month = Int(monthText) ?? months[String(monthText.prefix(3))],
                      var year = Int(yearText) else { continue }
                if year < 100 { year += 2000 }
                guard (1...12).contains(month), (1...31).contains(day) else { continue }
                var parts = DateComponents(year: year, month: month, day: day, hour: 12)
                parts.calendar = calendar
                guard parts.isValidDate(in: calendar), let date = calendar.date(from: parts) else { continue }
                if calendar.isDate(date, inSameDayAs: now) { return now }
                guard date <= now, let limit = calendar.date(byAdding: .year, value: -2, to: now), date >= limit else { continue }
                return date
            }
        }
        return nil
    }
}
