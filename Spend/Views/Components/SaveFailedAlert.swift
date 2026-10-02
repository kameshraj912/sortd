import SwiftUI

extension View {
    /// One alert for "the change was not written". Set the binding when a
    /// save or delete the user just asked for fails (`ModelContext.saveReporting`
    /// returns false), after the failure is in `ErrorLog`.
    func saveFailedAlert(_ isPresented: Binding<Bool>) -> some View {
        alert("Couldn't Save", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SaveFailedAlert.message)
        }
    }
}

enum SaveFailedAlert {
    static let title = "Couldn't Save"
    static let message = "Your change wasn't saved. Try again."
}
