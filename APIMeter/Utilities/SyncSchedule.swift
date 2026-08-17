import Foundation

/// Pure scheduling rule for the daily export sync:
/// run once per calendar day, at or after HH:mm local time.
/// Missed days run immediately at the next check (app launch / wake).
public enum SyncSchedule {
    public static let defaultHour = 0
    public static let defaultMinute = 30

    public static func isDue(lastSyncDay: String?, now: Date = Date(), hour: Int = defaultHour, minute: Int = defaultMinute) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let today = LocalDay(date: now)
        // Already ran today.
        if lastSyncDay == today.value { return false }
        // The scheduled moment of today.
        guard let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return false }
        return now >= scheduled
    }

    /// Next scheduled moment (for display).
    public static func nextRun(now: Date = Date(), hour: Int = defaultHour, minute: Int = defaultMinute) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        guard let todayRun = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if now < todayRun { return todayRun }
        return calendar.date(byAdding: .day, value: 1, to: todayRun)
    }
}
