import SwiftUI

@main
struct APIMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state: AppState?
    @State private var startupError: String?

    init() {
        do {
            let environment = try AppEnvironment.live()
            let appState = AppState(environment: environment)
            appState.floatingPanelController = FloatingPanelController(state: appState)
            AppState.current = appState
            _state = State(initialValue: appState)
        } catch {
            _state = State(initialValue: nil)
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            if let state {
                MenuBarView(state: state)
            } else if let startupError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Meter failed to start").font(.headline)
                    Text(startupError).font(.caption).foregroundStyle(.secondary)
                    Button("Quit") { NSApp.terminate(nil) }
                }
                .padding()
                .frame(width: 280)
            } else {
                ProgressView().padding()
            }
        } label: {
            Label("API Meter", systemImage: "chart.bar.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let state {
                SettingsView(state: state)
            } else {
                ProgressView()
            }
        }
    }
}
