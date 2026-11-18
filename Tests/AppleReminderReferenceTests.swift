import XCTest
@testable import LifeFlowCore

final class AppleReminderReferenceTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(secondsFromGMT: 0)!)
    private let morning = Date(timeIntervalSince1970: 1_792_540_800)

    func testReferenceRoundTripsOnlyUnderItsOwner() {
        let today = clock.today(morning)
        let task = FlowTask(title: "Test", day: today)
        let reference = FlowAppleReminderReference(task: task, displayedDay: today, clock: clock)
        let owner = UUID()
        XCTAssertEqual(FlowAppleReminderReference(url: reference.url(owner: owner), owner: owner), reference)
        XCTAssertNil(FlowAppleReminderReference(url: reference.url(owner: owner), owner: UUID()))
    }

    func testCompletedReminderKeepsItsOriginalDayAndAdvancesOnlyOneOccurrence() {
        let today = clock.today(morning)
        let completedAt = today.addingTimeInterval(12 * 3600)
        let tomorrow = clock.calendar.date(byAdding: .day, value: 1, to: today)!
        let openedAt = tomorrow.addingTimeInterval(9 * 3600)
        let task = FlowTask(title: "Daily", day: today, repeatRule: .daily)
        let reference = FlowAppleReminderReference(task: task, displayedDay: today, clock: clock)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(reference.complete(in: &data, at: completedAt, now: openedAt, clock: clock))
        XCTAssertFalse(reference.complete(in: &data, at: completedAt, now: openedAt, clock: clock))
        XCTAssertEqual(data.tasks.first?.day, tomorrow)
        XCTAssertEqual(data.history.filter { $0.outcome == .completed }.map(\.recordedAt), [completedAt])
    }

    func testPastReminderCannotCompleteTomorrowOrGuessAnEarlierTime() {
        let today = clock.today(morning)
        let tomorrow = clock.calendar.date(byAdding: .day, value: 1, to: today)!
        let afterBoundary = tomorrow.addingTimeInterval(4 * 3600)
        let task = FlowTask(title: "Old reminder", day: today)
        let reference = FlowAppleReminderReference(task: task, displayedDay: today, clock: clock)
        var data = FlowData(tasks: [task])
        XCTAssertFalse(reference.complete(in: &data, at: afterBoundary, now: afterBoundary, clock: clock))
        XCTAssertFalse(reference.complete(in: &data, at: nil, now: afterBoundary, clock: clock))
        XCTAssertEqual(data.tasks, [task])
    }

    func testHabitFollowsDailyRecordRules() {
        let today = clock.today(morning)
        let now = today.addingTimeInterval(12 * 3600)
        let task = FlowTask(title: "Habit", day: today, habitGoal: 3)
        let reference = FlowAppleReminderReference(task: task, displayedDay: today, clock: clock)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(reference.complete(in: &data, at: nil, now: now, clock: clock))
        XCTAssertFalse(reference.complete(in: &data, at: nil, now: now, clock: clock))
        XCTAssertEqual(data.habitDays.count, 1)
        XCTAssertEqual(data.habitDays.first?.day, today)
    }
}
