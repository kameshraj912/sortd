import Foundation
import Testing
@testable import Spend

/// A spreadsheet cell from a purchase must not run as a formula.
struct CSVEscapeTests {
    @Test func csvCellsCantRunAsFormulas() {
        #expect(CSVExport.escape("=HYPERLINK(\"http://x\")") == "\"'=HYPERLINK(\"\"http://x\"\")\"")
        #expect(CSVExport.escape("+61 shop") == "'+61 shop")
        #expect(CSVExport.escape("-5") == "'-5")
        #expect(CSVExport.escape("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSVExport.escape("Woolworths") == "Woolworths")
        #expect(CSVExport.escape("Coffee, cake") == "\"Coffee, cake\"")
    }
}
