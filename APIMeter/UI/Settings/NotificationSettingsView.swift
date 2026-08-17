import SwiftUI

/// Balance alert threshold (spec 52-54). nil threshold = alerts disabled.
/// Anti-spam: one alert per drop below the threshold (state machine in core).
struct NotificationSettingsView: View {
    @Bindable var state: AppState
    @State private var customThreshold = ""
    @State private var permissionNote = ""

    private var currentThreshold: Decimal? {
        state.environment.settings.balanceAlertThreshold
    }

    var body: some View {
        Form {
            Section("Balance Alert") {
                Picker("Alert when balance drops below", selection: Binding(
                    get: { thresholdPreset },
                    set: { preset in setThreshold(preset) }
                )) {
                    Text("Off").tag(ThresholdPreset.off)
                    Text("¥5").tag(ThresholdPreset.five)
                    Text("¥10").tag(ThresholdPreset.ten)
                    Text("¥20").tag(ThresholdPreset.twenty)
                    Text("Custom").tag(ThresholdPreset.custom)
                }
                if thresholdPreset == .custom {
                    TextField("Amount (e.g. 8.5)", text: $customThreshold)
                        .frame(width: 160)
                        .onSubmit {
                            if let value = Decimal(string: customThreshold, locale: Locale(identifier: "en_US_POSIX")) {
                                state.environment.settings.balanceAlertThreshold = value
                            }
                        }
                }
                Button("Allow Notifications") {
                    Task {
                        let granted = await state.environment.alertService.requestAuthorizationIfNeeded()
                        permissionNote = granted ? "Notifications allowed." : "Notifications are not allowed. Enable them in System Settings."
                    }
                }
                .glassButtonStyle()
                Text(permissionNote).font(.caption).foregroundStyle(.secondary)
                Text("You are notified once when the balance first drops below the threshold. No repeat spam - the alert re-arms after the balance rises above it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private enum ThresholdPreset: String, CaseIterable {
        case off, five, ten, twenty, custom
    }

    private var thresholdPreset: ThresholdPreset {
        switch currentThreshold {
        case nil: return .off
        case Decimal(5): return .five
        case Decimal(10): return .ten
        case Decimal(20): return .twenty
        default: return .custom
        }
    }

    private func setThreshold(_ preset: ThresholdPreset) {
        switch preset {
        case .off: state.environment.settings.balanceAlertThreshold = nil
        case .five: state.environment.settings.balanceAlertThreshold = 5
        case .ten: state.environment.settings.balanceAlertThreshold = 10
        case .twenty: state.environment.settings.balanceAlertThreshold = 20
        case .custom:
            customThreshold = currentThreshold.map(DecimalStorage.string) ?? ""
            state.environment.settings.balanceAlertThreshold = Decimal(string: customThreshold, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}
