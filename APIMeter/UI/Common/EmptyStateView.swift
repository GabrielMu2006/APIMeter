import SwiftUI

/// Empty state per spec 109.
struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Usage Data Yet", systemImage: "chart.bar")
        } description: {
            Text("Import your DeepSeek usage export\nor enable Local Usage Gateway.")
        } actions: {
            Button("Open Settings") {
                // Opens the app settings scene via environment action.
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}
