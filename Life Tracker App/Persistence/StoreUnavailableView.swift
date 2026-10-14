import SwiftUI

/// Shown when the data store cannot be opened. Nothing is deleted, so the
/// existing data is still on the device for diagnosis or a fixed migration.
struct StoreUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Unable to Open Your Data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your data was not changed or deleted. Install an update that fixes this, or contact the developer.")
        } actions: {
            Text(verbatim: String(describing: error))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding()
    }
}
