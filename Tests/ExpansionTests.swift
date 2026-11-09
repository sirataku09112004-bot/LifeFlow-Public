import XCTest
@testable import LifeFlowCore

final class ExpansionTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testV08MigrationPreservesTasksHistoryAndCategoryButtons() throws {
        let json = """
        {"schemaVersion":4,"categoryButtons":["仕事"],"tasks":[{
          "id":"00000000-0000-0000-0000-000000000001","title":"課題","note":"メモ",
          "day":"2026-11-09T00:00:00+09:00","favorite":true,"category":"仕事",
          "originDay":"2026-11-06T00:00:00+09:00","repeatRule":"weekly","repeatAnchorWeekday":6
        }],"history":[{
          "id":"00000000-0000-0000-0000-000000000002","taskID":"00000000-0000-0000-0000-000000000001",
          "title":"課題","day":"2026-11-06T00:00:00+09:00",
          "recordedAt":"2026-11-06T17:30:00+09:00","outcome":"failed"
        }]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(FlowData.self, from: Data(json.utf8)).validated()
        XCTAssertEqual(migrated.schemaVersion, 5)
        let task = try XCTUnwrap(migrated.tasks.first)
        XCTAssertEqual(task.note, "メモ")
        XCTAssertTrue(task.favorite)
        XCTAssertEqual(task.originDay, date("2026-11-06T00:00:00"))
        XCTAssertEqual(task.repeatRule, .weekly)
        XCTAssertEqual(task.repeatAnchorWeekday, 6)
        XCTAssertEqual(migrated.history.first?.outcome, .failed)
        XCTAssertEqual(migrated.registeredCategories, ["仕事"])
        XCTAssertTrue(migrated.annualGoals.isEmpty)
        XCTAssertTrue(migrated.habitDays.isEmpty)
    }

    func testGoalProgressAndToDoCompletionAreIndependent() throws {
        let now = date("2026-11-09T12:00:00")
        let openStep = FlowSubtask(title: "過去問")
        let goal = FlowGoal(title: "資格試験", deadline: clock.today(now), steps: [
            FlowSubtask(title: "参考書", isDone: true), openStep
        ])
        var data = FlowData(goals: [goal])
        XCTAssertEqual(goal.progress, 0.5)
        let task = try XCTUnwrap(data.todoForGoalStep(openStep.id, goalID: goal.id, today: clock.today(now)))
        data.tasks.append(task)
        XCTAssertNil(data.todoForGoalStep(openStep.id, goalID: goal.id, today: clock.today(now)))
        data.resolve(task.id, outcome: .completed, now: now, clock: clock)
        XCTAssertEqual(data.annualGoals, [goal])
        XCTAssertEqual(data.history.first?.outcome, .completed)
        XCTAssertTrue(data.tasks.isEmpty)
    }

    func testHabitOutcomesAtCutoffAndSkippedDay() throws {
        let monday = date("2026-11-09T00:00:00")
        let task = FlowTask(title: "筋トレ", day: monday, category: "習慣", habitGoal: 3)
        var data = FlowData(tasks: [task])
        let beforeCutoff = date("2026-11-10T03:59:59")
        data.resolve(task.id, outcome: .completed, now: beforeCutoff, clock: clock)
        data.resolve(task.id, outcome: .failed, now: beforeCutoff, clock: clock)
        XCTAssertEqual(data.habitDays.map(\.outcome), [.completed])
        XCTAssertEqual(data.habitDays.first?.day, monday)
        let tuesday = date("2026-11-10T04:00:00")
        XCTAssertTrue(data.markHabit(task.id, outcome: .rest, now: tuesday, clock: clock))
        XCTAssertEqual(data.history.count, 1)
        let wednesday = date("2026-11-11T12:00:00")
        let calendar = FlowHabitCalendar(taskID: task.id, days: data.habitDays, now: wednesday, clock: clock)
        XCTAssertEqual(calendar.streak, 1)
        let week = try XCTUnwrap(calendar.interval(month: false, offset: 0))
        XCTAssertEqual(calendar.counts(in: week).completed, 1)
        XCTAssertEqual(calendar.counts(in: week).failed, 0)
        let thursday = date("2026-11-12T12:00:00")
        data.rollover(now: thursday, clock: clock)
        XCTAssertEqual(data.tasks.first?.day, clock.today(thursday))
        XCTAssertEqual(data.habitDays.count, 2)
        let gap = FlowHabitCalendar(taskID: task.id, days: data.habitDays, now: thursday, clock: clock)
        XCTAssertEqual(gap.streak, 0)
        data.resolve(task.id, outcome: .failed, now: thursday, clock: clock)
        XCTAssertEqual(data.history.last?.outcome, .failed)
        XCTAssertEqual(data.habitDays.last?.outcome, .failed)
    }

    func testV09RoundTripIncludesHabitDaysAndGoals() throws {
        let now = date("2026-11-09T12:00:00")
        let goal = FlowGoal(title: "目標", deadline: clock.today(now))
        let task = FlowTask(title: "筋トレ", day: clock.today(now), habitGoal: 4)
        var data = FlowData(tasks: [task], goals: [goal])
        XCTAssertTrue(data.markHabit(task.id, outcome: .rest, now: now, clock: clock))
        let decoded = try JSONDecoder().decode(FlowData.self, from: JSONEncoder().encode(data)).validated()
        XCTAssertEqual(decoded.habitDays, data.habitDays)
        XCTAssertEqual(decoded.annualGoals, [goal])
        XCTAssertEqual(decoded.tasks, data.tasks)
    }

    func testCheckInSkipsOpenedBusinessDayAndRespectsBudget() {
        let opened = date("2026-11-09T03:59:00")
        let later = date("2026-11-09T04:00:00")
        let plan = FlowCheckIn.plan(now: later, lastOpened: opened, minuteOfDay: 21 * 60, clock: clock, available: 3)
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.first?.fireDate, date("2026-11-09T21:00:00"))
        XCTAssertEqual(Set(plan.map(\.identifier)).count, 3)
        let cancelled = FlowCheckIn.plan(now: later, lastOpened: later, minuteOfDay: 21 * 60, clock: clock, available: 3)
        XCTAssertEqual(cancelled.first?.fireDate, date("2026-11-10T21:00:00"))
        XCTAssertFalse(cancelled.contains { $0.identifier == plan.first?.identifier })
        XCTAssertTrue(FlowCheckIn.plan(now: later, lastOpened: nil, minuteOfDay: 21 * 60, clock: clock, available: 0).isEmpty)
    }
}
