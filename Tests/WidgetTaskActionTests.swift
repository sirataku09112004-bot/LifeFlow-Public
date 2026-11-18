import XCTest
@testable import LifeFlowCore

final class WidgetTaskActionTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testWidgetActionCompletesOnlyTheTappedRepeatingOccurrenceOnce() throws {
        let now = date("2026-11-16T20:00:00")
        let task = FlowTask(title: "毎日のタスク", day: clock.today(now), repeatRule: .daily)
        let data = FlowData(tasks: [task])

        let completed = try XCTUnwrap(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                                    data: data, now: now, clock: clock))
        XCTAssertEqual(completed.history.filter { $0.outcome == .completed && $0.taskID == task.id }.count, 1)
        XCTAssertEqual(completed.tasks.first?.day, date("2026-11-17T00:00:00"))
        XCTAssertNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                  data: completed, now: now, clock: clock))

        let tomorrow = date("2026-11-17T04:00:00")
        XCTAssertNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                   data: completed, now: tomorrow, clock: clock))
        let nextOccurrence = try XCTUnwrap(FlowWidgetTaskAction.complete(
            task.id, occurrenceDay: completed.tasks[0].day, data: completed, now: tomorrow, clock: clock
        ))
        XCTAssertEqual(nextOccurrence.history.filter { $0.outcome == .completed && $0.taskID == task.id }.count, 2)
        XCTAssertNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: completed.tasks[0].day,
                                                  data: nextOccurrence, now: tomorrow, clock: clock))
    }

    func testWidgetActionRecordsHabitAndRejectsStaleOccurrence() throws {
        let now = date("2026-11-16T20:00:00")
        let habit = FlowTask(title: "習慣", day: clock.today(now), habitGoal: 3)
        let data = FlowData(tasks: [habit])
        let completed = try XCTUnwrap(FlowWidgetTaskAction.complete(habit.id, occurrenceDay: habit.day,
                                                                    data: data, now: now, clock: clock))
        XCTAssertEqual(completed.habitDays.count, 1)
        XCTAssertEqual(completed.habitDays.first?.outcome, .completed)
        XCTAssertEqual(completed.history.last?.outcome, .completed)

        let moved = FlowTask(id: habit.id, title: habit.title, day: date("2026-11-17T00:00:00"), habitGoal: 3)
        XCTAssertNil(FlowWidgetTaskAction.complete(habit.id, occurrenceDay: habit.day,
                                                   data: FlowData(tasks: [moved]), now: now, clock: clock))
    }

    func testYesterdayWidgetCannotCompleteAStillMatchingOccurrence() throws {
        let before = date("2026-11-17T03:59:59")
        let after = date("2026-11-17T04:00:00")
        let task = FlowTask(title: "予定", day: clock.today(after), plannedDay: clock.today(before))
        let data = FlowData(tasks: [task])
        XCTAssertNotNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                      displayedDay: clock.today(before), data: data,
                                                      now: before, clock: clock))
        XCTAssertNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                   displayedDay: clock.today(before), data: data,
                                                   now: after, clock: clock))
        XCTAssertNotNil(FlowWidgetTaskAction.complete(task.id, occurrenceDay: task.day,
                                                      displayedDay: clock.today(after), data: data,
                                                      now: after, clock: clock))
    }
}
