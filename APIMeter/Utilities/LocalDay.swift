import Foundation

/// A calendar day in the user's local timezone, stored as "yyyy-MM-dd".
/// Sorting by string value is chronologically correct (zero-padded format).
/// Day buckets are computed once at import time; changing the system timezone
/// later must never corrupt already-bucketed history (spec §107).
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d),
              // reject obviously invalid days via Calendar validation
              LocalDay.isValidDate(year: y, month: m, day: d)
        else { return nil }
        self.value = String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func make(_ year: Int, _ month: Int, _ day: Int) -> LocalDay {
        LocalDay(String(format: "%04d-%02d-%02d", year, month, day))!
    }

    public init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.value = String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: comps) != nil
    }

    public var description: String { value }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.value < rhs.value }

    /// Start instant (UTC) of this day in the given timezone.
    public func start(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = value.split(separator: "-")
        let comps = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))
        return calendar.date(from: comps)!
    }

    /// Day offset by n days in the given timezone.
    public func adding(days: Int, in timeZone: TimeZone = .autoupdatingCurrent) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let d = start(in: timeZone)
        return LocalDay(date: calendar.date(byAdding: .day, value: days, to: d)!, timeZone: timeZone)
    }
}
