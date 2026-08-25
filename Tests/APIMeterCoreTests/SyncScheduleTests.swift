import Foundation
import Testing
import APIMeterCore

struct SyncScheduleTests {

    private func date(_ iso: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = iso.split(separator: "T").flatMap { $0.split(separator: "-").flatMap { $0.split(separator: ":") } }
        let comps = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]), hour: Int(parts[3]), minute: Int(parts[4]))
        return calendar.date(from: comps)!
    }

    @Test func runsOncePerDayAfterScheduledTime() {
        let now = date("2026-08-17T00:30")
        #expect(SyncSchedule.isDue(lastSyncDay: nil, now: now))
        #expect(SyncSchedule.isDue(lastSyncDay: "2026-08-16", now: now))
        // Already ran today -> not due again.
        #expect(SyncSchedule.isDue(lastSyncDay: "2026-08-17", now: now) == false)
    }

    @Test func notDueBeforeScheduledTime() {
        let now = date("2026-08-17T00:29")
        #expect(SyncSchedule.isDue(lastSyncDay: nil, now: now) == false)
    }

    @Test func missedDaysRunImmediately() {
        // App was closed yesterday; launches at 09:00 -> due now (catch-up).
        let now = date("2026-08-17T09:00")
        #expect(SyncSchedule.isDue(lastSyncDay: "2026-08-15", now: now))
    }

    @Test func failureTodaySuppressesTimerRetry() {
        // Session expired at 00:35; the 10-min timer must NOT re-run today.
        let now = date("2026-08-17T00:40")
        #expect(SyncSchedule.shouldRun(lastSyncDay: nil, lastFailureDay: "2026-08-17", now: now) == false)
    }

    @Test func forcedRunBypassesFailureCooldown() {
        // Launch catch-up is force=true: after a re-login the same day recovers.
        let now = date("2026-08-17T11:00")
        #expect(SyncSchedule.shouldRun(lastSyncDay: nil, lastFailureDay: "2026-08-17", now: now, force: true))
    }

    @Test func failureCooldownExpiresNextDay() {
        // Yesterday's failure must not block today's scheduled run.
        let now = date("2026-08-18T00:30")
        #expect(SyncSchedule.shouldRun(lastSyncDay: nil, lastFailureDay: "2026-08-17", now: now))
    }

    @Test func noFailureMeansRunsRegardless() {
        let now = date("2026-08-17T00:30")
        #expect(SyncSchedule.shouldRun(lastSyncDay: nil, lastFailureDay: nil, now: now))
    }

    @Test func failureCooldownNeverOverridesNotDue() {
        let now = date("2026-08-17T00:29")
        #expect(SyncSchedule.shouldRun(lastSyncDay: nil, lastFailureDay: "2026-08-16", now: now) == false)
    }

    @Test func nextRunIsTomorrowAfterTodayPassed() {
        let now = date("2026-08-17T09:00")
        let next = SyncSchedule.nextRun(now: now)
        let expected = date("2026-08-18T00:30")
        #expect(next == expected)
    }
}
