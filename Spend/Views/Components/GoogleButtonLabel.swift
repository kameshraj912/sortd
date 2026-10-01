import SwiftUI

/// "Continue with Google", drawn to Google's sign-in branding rules:
/// the official G (cropped unchanged from Google's
/// asset pack), light theme white with a #747775 border and #1F1F1F text,
/// dark theme #131314 with #8E918F and #E3E3E3, 16 / 12 / 16 pt spacing.
/// Google's guidelines allow the pill shape; this draws it so it sits next to Sign
/// in with Apple as a matched pair, same height and corner radius. Draws its
/// own background and border: apply `.googleButton()`, not `.primaryGlass()`,
/// or the glass style wraps it in a second, darker capsule.
/// https://developers.google.com/identity/branding-guidelines
struct GoogleButtonLabel: View {
    var working = false
    @Environment(\.colorScheme) private var scheme

    /// A capsule, like every other button in the app and like the Apple button
    /// next to it (both makers allow it: Google's "pill" shape, Apple's
    /// configurable corner radius). Three different corners on one page read
    /// as three different apps (feel check, 27 Sep).

    var body: some View {
        let dark = scheme == .dark
        let shape = Capsule()
        HStack(spacing: 12) {
            if working {
                ProgressView().frame(width: 20, height: 20)
            } else {
                Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(working ? "Opening Google…" : "Continue with Google")
                .font(.body.weight(.medium))
                .foregroundStyle(Color(hex: dark ? 0xE3E3E3 : 0x1F1F1F))
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(hex: dark ? 0x131314 : 0xFFFFFF), in: shape)
        .overlay(shape.strokeBorder(Color(hex: dark ? 0x8E918F : 0x747775), lineWidth: 1))
        .contentShape(shape)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
