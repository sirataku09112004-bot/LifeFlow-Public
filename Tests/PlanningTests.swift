import XCTest
@testable import LifeFlowCore

final class PlanningTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testTodayPlanExpiresAtFourAndLeavesDeadlineAndOrigin() throws {
        let now = date("2026-11-16T20:00:00")
        let tomorrow = date("2026-11-17T00:00:00")
        let origin = date("2026-11-13T00:00:00")
        let task = FlowTask(title: "提出", day: tomorrow, favorite: true, originDay: origin)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.setPlannedToday(task.id, enabled: true, now: now, clock: clock))
        let planned = try XCTUnwrap(data.tasks.first)
        XCTAssertEqual(planned.deadline, origin)
        XCTAssertEqual(planned.day, tomorrow)
        let before = date("2026-11-17T03:59:59")
        XCTAssertEqual(FlowTaskList(tasks: data.tasks, query: "", now: before, clock: clock).today, [planned])
        XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: before, clock: clock))
        let event = try XCTUnwrap(data.history.last)
        XCTAssertTrue(data.undoCompletion(event.id, now: before, clock: clock))
        XCTAssertEqual(data.tasks, [planned])
        XCTAssertTrue(data.rollover(now: date("2026-11-17T04:00:00"), clock: clock))
        XCTAssertNil(data.tasks.first?.plannedDay)
        XCTAssertEqual(data.tasks.first?.deadline, origin)
    }

    func testDeadlineChangeAndTodayPlanAreIndependent() {
        let now = date("2026-11-16T20:00:00")
        let task = FlowTask(title: "週の作業", day: clock.today(now), originDay: date("2026-11-15T00:00:00"), repeatRule: .weekly)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.setPlannedToday(task.id, enabled: true, now: now, clock: clock))
        let friday = date("2026-11-20T00:00:00")
        XCTAssertTrue(data.changeDeadline(task.id, to: friday, clock: clock))
        XCTAssertEqual(data.tasks.first?.deadline, friday)
        XCTAssertEqual(data.tasks.first?.repeatAnchorWeekday, 6)
        XCTAssertEqual(data.tasks.first?.plannedDay, clock.today(now))
        XCTAssertTrue(data.setPlannedToday(task.id, enabled: false, now: now, clock: clock))
        XCTAssertEqual(data.tasks.first?.deadline, friday)
        XCTAssertTrue(FlowTaskList(tasks: data.tasks, query: "", now: now, clock: clock).today.isEmpty)
    }

    func testFilteredReorderingPreservesOtherSlotsAfterReloadAndAppend() throws {
        let now = date("2026-11-16T20:00:00")
        let today = clock.today(now)
        let a = FlowTask(title: "A", day: today, category: "仕事")
        let b = FlowTask(title: "B", day: today, favorite: true, category: "生活")
        let c = FlowTask(title: "C", day: today, category: "仕事")
        var data = FlowData(tasks: [a, b, c], todayOrder: [a.id, b.id, c.id])
        XCTAssertTrue(data.reorderToday([a.id, c.id], to: [c.id, a.id], now: now, clock: clock))
        data = try JSONDecoder().decode(FlowData.self, from: JSONEncoder().encode(data)).validated()
        let added = FlowTask(title: "0", day: today, priority: .high)
        data.tasks.append(added)
        let order = data.todayOrder ?? []
        XCTAssertEqual(FlowTaskList(tasks: data.tasks, query: "", now: now, clock: clock, todayOrder: order).today.map(\.id),
                       [c.id, b.id, a.id, added.id])
    }

    func testPastHabitEditsOnlyItsCalendarAndNeverDuplicates() throws {
        let now = date("2026-11-16T20:00:00")
        let today = clock.today(now)
        let past = date("2026-11-15T00:00:00")
        let habit = FlowTask(title: "習慣", day: today, habitGoal: 3)
        let goal = FlowGoal(title: "年間目標", deadline: today)
        var data = FlowData(tasks: [habit], goals: [goal])
        XCTAssertFalse(data.editPastHabit(habit.id, day: today, outcome: .completed, now: now, clock: clock))
        XCTAssertTrue(data.editPastHabit(habit.id, day: past, outcome: .failed, now: now, clock: clock))
        XCTAssertTrue(data.editPastHabit(habit.id, day: past, outcome: .completed, now: now, clock: clock))
        data = try JSONDecoder().decode(FlowData.self, from: JSONEncoder().encode(data)).validated()
        XCTAssertEqual(data.habitDays.count, 1)
        XCTAssertEqual(FlowHabitCalendar(taskID: habit.id, days: data.habitDays, now: now, clock: clock).streak, 1)
        XCTAssertTrue(data.editPastHabit(habit.id, day: past, outcome: .rest, now: now, clock: clock))
        XCTAssertEqual(data.habitDays.first?.outcome, .rest)
        XCTAssertTrue(data.editPastHabit(habit.id, day: past, outcome: nil, now: now, clock: clock))
        XCTAssertTrue(data.habitDays.isEmpty)
        XCTAssertTrue(data.history.isEmpty)
        XCTAssertEqual(data.tasks, [habit])
        XCTAssertEqual(data.annualGoals, [goal])
    }

    func testWidgetSnapshotReflectsEditsPrivacyAndFourAM() throws {
        let now = date("2026-11-16T20:00:00")
        let tomorrow = date("2026-11-17T00:00:00")
        let deadline = date("2026-11-20T00:00:00")
        let future = FlowTask(title: "非公開の名前", day: deadline)
        let upcoming = FlowTask(title: "明日のタスク", day: tomorrow)
        var data = FlowData(tasks: [future, upcoming])
        XCTAssertTrue(data.setPlannedToday(future.id, enabled: true, now: now, clock: clock))
        let snapshot = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        XCTAssertEqual(snapshot.entry(now: now, clock: clock)?.tasks.map(\.id), [future.id])
        XCTAssertEqual(snapshot.entry(now: date("2026-11-17T03:59:59"), clock: clock)?.tasks.map(\.id), [future.id])
        XCTAssertEqual(snapshot.entry(now: date("2026-11-17T04:00:00"), clock: clock)?.tasks.map(\.id), [upcoming.id])
        let hidden = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: false)
        XCTAssertEqual(hidden.entry(now: now, clock: clock)?.remaining, 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self).contains(future.id.uuidString))
        XCTAssertTrue(data.resolve(future.id, outcome: .completed, now: now, clock: clock))
        let complete = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        XCTAssertEqual(complete.entry(now: now, clock: clock)?.remaining, 0)
        XCTAssertEqual(complete.entry(now: now, clock: clock)?.percent, 100)
        let event = try XCTUnwrap(data.history.last)
        XCTAssertTrue(data.undoCompletion(event.id, now: now, clock: clock))
        XCTAssertEqual(FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true), snapshot)
    }

    func testWidgetRoutingAndAltStoreGroupNames() {
        let id = UUID()
        XCTAssertEqual(FlowWidgetRoute(FlowWidgetRoute.url(for: id))?.taskID, id)
        XCTAssertNotNil(FlowWidgetRoute(FlowWidgetRoute.url()))
        XCTAssertNil(FlowWidgetRoute(URL(string: "lifeflow://todo/wrong")!))
        let base = FlowWidgetContainer.identifier
        XCTAssertEqual(FlowWidgetContainer.groupIDs(["group.other", base + ".TEAM"]), [base + ".TEAM", base])
    }
}
