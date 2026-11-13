import XCTest
@testable import LifeFlowCore

final class DeadlineTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testDeadlineUsesLocalCalendarAtFourAM() {
        let deadline = date("2026-11-20T00:00:00")
        for (time, expected) in [
            ("2026-11-15T12:00:00", 5), ("2026-11-18T12:00:00", 2),
            ("2026-11-20T03:59:59", 1), ("2026-11-20T04:00:00", 0),
            ("2026-11-21T04:00:00", -1), ("2026-11-23T04:00:00", -3)
        ] {
            XCTAssertEqual(clock.daysUntilDeadline(deadline, now: date(time)), expected, time)
        }
    }

    func testEarlyCompletionUpdatesCategoryProgressAndUndoAfterReload() throws {
        let now = date("2026-11-15T12:00:00")
        let task = FlowTask(title: "提出", day: date("2026-11-20T00:00:00"), category: "学業")
        let today = FlowTask(title: "今日の課題", day: clock.today(now), category: "学業")
        let goal = FlowGoal(title: "目標", deadline: task.day)
        let habit = FlowHabitRecord(taskID: UUID(), day: clock.today(now), outcome: .rest)
        var data = FlowData(tasks: [task, today], goals: [goal], habitRecords: [habit])

        func progress(_ category: FlowCategoryFilter) -> FlowTodayProgress {
            let list = FlowTaskList(tasks: data.tasks, query: "", category: category, now: now, clock: clock)
            return FlowTodayProgress(data: data, pending: list.today,
                                     completed: data.completedToday(now: now, clock: clock, category: category),
                                     now: now, clock: clock, category: category, favoritesOnly: false)
        }
        XCTAssertEqual(progress(.named("学業")).total, 1)
        XCTAssertEqual(data.resolveDisplayedTask(task, outcome: .completed, now: now,
                                                 clock: clock, maxCarries: 100), .resolved)
        let event = try XCTUnwrap(data.completedToday(now: now, clock: clock).first)
        XCTAssertEqual(event.deadline, task.day)
        XCTAssertEqual(event.recordedAt, now)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        data = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
        XCTAssertEqual(data.completedToday(now: now, clock: clock).map(\.id), [event.id])
        XCTAssertEqual(progress(.named("学業")).total, 2)
        XCTAssertEqual(progress(.named("学業")).percent, 50)
        XCTAssertEqual(progress(.named("生活")).total, 0)
        XCTAssertTrue(data.undoCompletion(event.id, now: now, clock: clock))
        XCTAssertEqual(data.tasks.first { $0.id == task.id }, task)
        XCTAssertEqual(progress(.named("学業")).total, 1)
        XCTAssertEqual(progress(.named("学業")).percent, 0)
        XCTAssertEqual(data.annualGoals, [goal])
        XCTAssertEqual(data.habitDays, [habit])
    }

    func testEarlyRepeatAdvancesFromDeadlineAndRejectsNextOccurrenceOnSameDay() throws {
        let now = date("2026-11-15T12:00:00")
        let task = FlowTask(title: "毎日", day: date("2026-11-20T00:00:00"), repeatRule: .daily)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        let event = try XCTUnwrap(data.history.last)
        let next = try XCTUnwrap(data.tasks.first)
        XCTAssertEqual(next.deadline, date("2026-11-21T00:00:00"))
        for _ in 0..<25 {
            XCTAssertEqual(data.resolveDisplayedTask(task, outcome: .completed, now: now,
                                                     clock: clock, maxCarries: 100), .stale)
            XCTAssertEqual(data.resolveDisplayedTask(next, outcome: .completed, now: now,
                                                     clock: clock, maxCarries: 100), .blocked(.alreadyCompleted))
        }
        XCTAssertEqual(data.history.count, 1)
        XCTAssertTrue(data.undoCompletion(event.id, now: now, clock: clock))
        XCTAssertEqual(data.tasks, [task])
    }

    func testRolloverKeepsOriginalDeadlineAndDoesNotGrowDailyHistory() throws {
        let deadline = date("2026-11-13T00:00:00")
        for rule: FlowRepeat? in [nil, .weekly] {
            let task = FlowTask(title: "締切", day: deadline, repeatRule: rule)
            var data = FlowData(tasks: [task])
            let saturday = date("2026-11-14T12:00:00")
            XCTAssertTrue(data.rollover(now: saturday, clock: clock))
            XCTAssertEqual(data.tasks.first?.day, date("2026-11-16T00:00:00"))
            XCTAssertEqual(data.tasks.first?.deadline, deadline)
            XCTAssertEqual(data.history.map(\.outcome), [.carried])

            let tuesday = date("2026-11-17T12:00:00")
            XCTAssertTrue(data.rollover(now: tuesday, clock: clock))
            XCTAssertEqual(data.tasks.first?.day, clock.today(tuesday))
            XCTAssertEqual(data.tasks.first?.deadline, deadline)
            XCTAssertEqual(clock.daysUntilDeadline(data.tasks[0].deadline, now: tuesday), -4)
            XCTAssertEqual(data.history.map(\.outcome), [.carried])

            XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: tuesday, clock: clock))
            let event = try XCTUnwrap(data.history.last)
            XCTAssertEqual(event.deadline, deadline)
            XCTAssertEqual(event.day, clock.today(tuesday))
            if rule == .weekly {
                XCTAssertEqual(data.tasks.first?.deadline, date("2026-11-20T00:00:00"))
                XCTAssertNil(data.tasks.first?.originDay)
            } else {
                XCTAssertTrue(data.tasks.isEmpty)
            }
            XCTAssertTrue(data.undoCompletion(event.id, now: tuesday, clock: clock))
            XCTAssertEqual(data.tasks.first?.deadline, deadline)
            XCTAssertEqual(data.history.map(\.outcome), [.carried])
        }
    }
}
