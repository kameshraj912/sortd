import Foundation

/// Where this copy of Sortd came from. The App Store's receipt file is named
/// "receipt"; TestFlight and development builds get "sandboxReceipt", and a
/// simulator has none. Used to hide things that only work for a store copy.
enum Distribution {
    static func isAppStore(receiptName: String?) -> Bool {
        receiptName == "receipt"
    }

    static var isAppStore: Bool {
        isAppStore(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }

    /// A TestFlight (or developer-signed) install, by its sandbox receipt.
    /// Said positively, so an unknown receipt counts as "not TestFlight":
    /// anything that must stay off for App Store copies gates on this.
    static func isTestFlight(receiptName: String?) -> Bool {
        receiptName == "sandboxReceipt"
    }

    static var isTestFlight: Bool {
        isTestFlight(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }
}
