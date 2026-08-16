import SwiftUI

@main
struct APIMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state: AppState?
    @State private var startupError: String?
    private let openDashboardAtLaunch: Bool

    init() {
        // Verification aid: APIMETER_OPEN_DASHBOARD=1 presents the dashboard
        // window at launch. Product default stays menu-bar-first.
        self.openDashboardAtLaunch = ProcessInfo.processInfo.environment["APIMETER_OPEN_DASHBOARD"] == "1"
        do {
            let environment = try AppEnvironment.live()
            _state = State(initialValue: AppState(environment: environment))
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

        Window("API Meter", id: "dashboard") {
            if let state {
                DashboardView(state: state)
            } else {
                ProgressView()
            }
        }
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(openDashboardAtLaunch ? .presented : .automatic)

        Settings {
            if let state {
                SettingsView(state: state)
            } else {
                ProgressView()
            }
        }
    }
}
