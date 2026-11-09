import XCTest
@testable import LifeFlowCore

final class ReminderSettingsTests: XCTestCase {
    let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "+09:00")! }
    func testLegacyHourAndSettingsRoundTrip() throws {
        XCTAssertEqual(FlowReminderSettings.load(nil, legacyHour: 14).hour, 14)
        XCTAssertEqual(FlowReminderSettings.load(nil, legacyHour: 3).hour, 9)
        var s = FlowReminderSettings()
        s.hour = 0; s.minute = 7; s.onDueDay = false; s.onPreviousDay = true
        s.previousHour = 22; s.previousMinute = 38; s.weekdays = [2, 6]
        s.favoritesOnly = true; s.sound = false; s.showTitle = false
        XCTAssertEqual(FlowReminderSettings.load(try JSONEncoder().encode(s), legacyHour: 9), s)
        XCTAssertEqual(FlowReminderSettings.load(Data("broken".utf8), legacyHour: 14).hour, 14)
    }
    func testNormalizeInvalidAndEmptyWeekdays() {
        var s = FlowReminderSettings()
        s.hour = 24; s.minute = -1; s.previousHour = -1; s.previousMinute = 60
        s.weekdays = [0, 2, 2, 8]
        let normalized = s.normalized()
        XCTAssertEqual(normalized.hour, 9); XCTAssertEqual(normalized.minute, 0)
        XCTAssertEqual(normalized.previousHour, 18); XCTAssertEqual(normalized.previousMinute, 0)
        XCTAssertEqual(normalized.weekdays, [2])
        s.weekdays = []; XCTAssertEqual(s.normalized().weekdays, [])
    }
    func testMinuteAndCalendarDateBeforeFourAM() {
        let task = FlowTask(title: "深夜", day: date("2026-11-05T00:00:00"))
        var s = FlowReminderSettings(); s.hour = 0; s.minute = 15
        let plan = FlowReminderPlan.make(tasks: [task], settings: s, now: date("2026-11-04T23:59:00"), clock: clock)
        XCTAssertEqual(plan.first?.fireDate, date("2026-11-05T00:15:00"))
        XCTAssertTrue(FlowReminderPlan.make(tasks: [task], settings: s, now: date("2026-11-05T00:15:00"), clock: clock).isEmpty)
    }
    func testPreviousDayYearBoundaryAndDistinctIDs() {
        let task = FlowTask(title: "年明け", day: date("2027-01-01T00:00:00"))
        var s = FlowReminderSettings(); s.onPreviousDay = true; s.previousMinute = 42
        let plan = FlowReminderPlan.make(tasks: [task], settings: s, now: date("2026-12-30T00:00:00"), clock: clock)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].fireDate, date("2026-12-31T18:42:00"))
        XCTAssertTrue(plan[0].previousDay); XCTAssertFalse(plan[1].previousDay)
        XCTAssertEqual(Set(plan.map(\.requestID)).count, 2)
        XCTAssertEqual(Set(plan.map(\.id)), [task.id])
    }
    func testWeekdaysApplyToActualFireDay() {
        let task = FlowTask(title: "月曜", day: date("2026-11-09T00:00:00"))
        var s = FlowReminderSettings(); s.onPreviousDay = true; s.weekdays = [2, 3, 4, 5, 6]
        let plan = FlowReminderPlan.make(tasks: [task], settings: s, now: date("2026-11-07T00:00:00"), clock: clock)
        XCTAssertEqual(plan.count, 1); XCTAssertFalse(plan[0].previousDay)
        s.weekdays = [1]
        let sunday = FlowReminderPlan.make(tasks: [task], settings: s, now: date("2026-11-07T00:00:00"), clock: clock)
        XCTAssertEqual(sunday.count, 1); XCTAssertTrue(sunday[0].previousDay)
    }
    func testFiltersAndDisabledTimings() {
        let tasks = [FlowTask(title: "普通", day: date("2026-11-05T00:00:00")),
                     FlowTask(title: "大事", day: date("2026-11-05T00:00:00"), favorite: true)]
        let now = date("2026-11-04T00:00:00")
        var s = FlowReminderSettings(); s.favoritesOnly = true
        XCTAssertEqual(FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock).map(\.title), ["大事"])
        s.onDueDay = false
        XCTAssertTrue(FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock).isEmpty)
        s.onPreviousDay = true; s.weekdays = []
        XCTAssertTrue(FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock).isEmpty)
    }
    func testGlobalLimitAndStableOrderWithTwoNotifications() {
        let tasks = (0..<40).map { FlowTask(title: "\($0)", day: date("2026-11-05T00:00:00")) }
        var s = FlowReminderSettings(); s.onPreviousDay = true
        let now = date("2026-11-04T00:00:00")
        let a = FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock, limit: 100)
        let b = FlowReminderPlan.make(tasks: Array(tasks.reversed()), settings: s, now: now, clock: clock)
        XCTAssertEqual(a.count, 60); XCTAssertEqual(a.map(\.requestID), b.map(\.requestID))
        XCTAssertEqual(a.filter(\.previousDay).count, 40)
        XCTAssertEqual(FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock, limit: 3).count, 3)
        XCTAssertTrue(FlowReminderPlan.make(tasks: tasks, settings: s, now: now, clock: clock, limit: 0).isEmpty)
    }
    func testRemovalAndPastPreviousNotification() {
        let task = FlowTask(title: "明日", day: date("2026-11-05T00:00:00"))
        var s = FlowReminderSettings(); s.onPreviousDay = true
        let now = date("2026-11-04T19:00:00")
        let plan = FlowReminderPlan.make(tasks: [task], settings: s, now: now, clock: clock)
        XCTAssertEqual(plan.count, 1); XCTAssertFalse(plan[0].previousDay)
        XCTAssertTrue(FlowReminderPlan.make(tasks: [], settings: s, now: now, clock: clock).isEmpty)
    }
}
