import SwiftUI

extension View {
    /// A picker row that never cuts its value off. At the accessibility
    /// sizes a menu picker squeezed "AUD · Australian Dollar" to "AUD · A…"
    /// beside its label (U13); there the picker becomes a row that opens
    /// its own list, where every choice wraps in full.
    func accessiblePickerStyle() -> some View {
        modifier(AccessiblePickerStyle())
    }
}

private struct AccessiblePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.navigationLink)
        } else {
            content.pickerStyle(.menu)
        }
    }
}
