import SwiftUI

/// Gateway settings (spec 24): enable, port, status, endpoint, copy.
/// Gateway failures never affect balance / CSV / dashboard (spec 83).
struct GatewaySettingsView: View {
    @Bindable var state: AppState
    @State private var portText = ""
    @State private var copyFeedback = false

    private var gateway: GatewayManager { state.environment.gatewayManager }

    var body: some View {
        Form {
            Section("Local Usage Gateway") {
                Toggle("Enable Gateway", isOn: Binding(
                    get: { gateway.isRunning },
                    set: { enabled in
                        Task {
                            if enabled {
                                await gateway.start()
                            } else {
                                await gateway.stop()
                            }
                        }
                    }
                ))
                TextField("Port", text: $portText)
                    .frame(width: 120)
                    .onSubmit { applyPort() }
                    .onAppear { portText = String(state.environment.settings.gatewayPort) }
                LabeledContent("Status", value: statusText)
                LabeledContent("Endpoint", value: gateway.endpoint ?? "http://127.0.0.1:" + String(state.environment.settings.gatewayPort))
                HStack {
                    Button("Copy Endpoint") {
                        let endpoint = gateway.endpoint ?? "http://127.0.0.1:" + String(state.environment.settings.gatewayPort)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(endpoint, forType: .string)
                        copyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copyFeedback = false }
                    }
                    if copyFeedback {
                        Text("Copied").font(.caption).foregroundStyle(.green)
                    }
                }
            }
            Section("About the Gateway") {
                Text("Listens on 127.0.0.1 only and transparently forwards requests to DeepSeek. Prompts and completions are never stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = gateway.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var statusText: String {
        switch gateway.status {
        case .running: return "● Running"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }

    private func applyPort() {
        guard let port = Int(portText), port > 0, port <= 65535 else { return }
        state.environment.settings.gatewayPort = port
        if gateway.isRunning {
            Task {
                await gateway.stop()
                await gateway.start()
            }
        }
    }
}
