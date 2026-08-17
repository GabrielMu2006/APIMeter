import Foundation
import Observation
import Testing
import APIMeterCore

/// Sendable-safe flag for withObservationTracking callbacks.
private final class Flag: @unchecked Sendable {
    var value = false
}

/// Verifies the two UI bugs' root cause stays fixed: settings must be
/// observable (views re-render on change) and persisted (UserDefaults).
@MainActor
struct AppSettingsTests {

    @Test func thresholdChangeIsObservable() {
        let defaults = UserDefaults(suiteName: "test-settings-" + UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.balanceAlertThreshold = 10

        let flag = Flag()
        withObservationTracking {
            _ = settings.balanceAlertThreshold
        } onChange: {
            flag.value = true
        }
        settings.balanceAlertThreshold = 20

        #expect(flag.value)
        #expect(settings.balanceAlertThreshold == 20)
    }

    @Test func appearanceChangeIsObservable() {
        let defaults = UserDefaults(suiteName: "test-settings-" + UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .system

        let flag = Flag()
        withObservationTracking {
            _ = settings.appearance
        } onChange: {
            flag.value = true
        }
        settings.appearance = .dark

        #expect(flag.value)
        #expect(settings.appearance == .dark)
    }

    @Test func settingsPersistAcrossInstances() {
        let suite = "test-settings-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let first = AppSettings(defaults: defaults)
        first.balanceAlertThreshold = 20
        first.appearance = .light
        first.retention = .days90

        let second = AppSettings(defaults: defaults)
        #expect(second.balanceAlertThreshold == 20)
        #expect(second.appearance == .light)
        #expect(second.retention == .days90)
    }

    @Test func defaultsAreSane() {
        let defaults = UserDefaults(suiteName: "test-settings-" + UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.retention == .forever)
        #expect(settings.balanceAlertThreshold == nil)
        #expect(settings.appearance == .system)
    }
}
