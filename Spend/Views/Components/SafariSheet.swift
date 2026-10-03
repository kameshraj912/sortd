import SwiftUI
import SafariServices

/// A web page to show in the in-app Safari sheet (`SFSafariViewController`).
/// Used where the page must not go to the person's default browser.
struct SafariPage: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

/// `SFSafariViewController` as a sheet's content. Web links only.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
