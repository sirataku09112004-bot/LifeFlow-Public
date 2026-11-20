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
        XCTAssertEqual(snapshot.entry(now: now, clock: clock)?.upcomingTasks?.map(\.id), [upcoming.id])
        XCTAssertEqual(snapshot.entry(now: date("2026-11-17T03:59:59"), clock: clock)?.tasks.map(\.id), [future.id])
        XCTAssertEqual(snapshot.entry(now: date("2026-11-17T04:00:00"), clock: clock)?.tasks.map(\.id), [upcoming.id])
        XCTAssertEqual(snapshot.entry(now: date("2026-11-17T04:00:00"), clock: clock)?.upcomingTasks?.map(\.id), [future.id])
        let hidden = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: false)
        XCTAssertEqual(hidden.entry(now: now, clock: clock)?.remaining, 1)
        XCTAssertEqual(hidden.entry(now: now, clock: clock)?.upcomingTasks, [])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self).contains(future.id.uuidString))
        XCTAssertTrue(data.resolve(future.id, outcome: .completed, now: now, clock: clock))
        let complete = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        XCTAssertEqual(complete.entry(now: now, clock: clock)?.remaining, 0)
        XCTAssertEqual(complete.entry(now: now, clock: clock)?.percent, 100)
        let event = try XCTUnwrap(data.history.last)
        XCTAssertTrue(data.undoCompletion(event.id, now: now, clock: clock))
        XCTAssertEqual(FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true), snapshot)
    }

    func testWidgetUpcomingShowsSixNearestDatesAndDecodesOldSnapshot() throws {
        let now = date("2026-11-16T20:00:00")
        let scheduled = try (1...7).map { offset in
            let day = try XCTUnwrap(clock.calendar.date(byAdding: .day, value: offset, to: clock.today(now)))
            return FlowTask(title: "今後のタスク \(offset)", day: day)
        }
        let data = FlowData(tasks: Array(scheduled.reversed()))
        let snapshot = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        let today = try XCTUnwrap(snapshot.entry(now: now, clock: clock))
        XCTAssertEqual(today.remaining, 0)
        XCTAssertEqual(today.upcomingTasks?.map(\.id), Array(scheduled.prefix(6)).map(\.id))
        XCTAssertEqual(today.upcomingTasks?.first?.occurrenceDay, scheduled.first?.day)
        let old = FlowWidgetDay(day: today.day, remaining: 0, percent: 0, titlesVisible: true, tasks: [])
        let decoded = try JSONDecoder().decode(FlowWidgetDay.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.upcomingTasks)
    }

    func testUndatedTaskCanBePlannedAndCompletedWithoutAcquiringADeadline() throws {
        let now = date("2026-11-16T20:00:00")
        let anchor = date("2026-11-14T00:00:00")
        let task = FlowTask(title: "期限なしのToDo", day: anchor, noDeadline: true)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.rollover(now: now, clock: clock))
        XCTAssertEqual(data.tasks, [task])
        XCTAssertTrue(data.history.isEmpty)
        func snapshot(_ data: FlowData) throws -> FlowWidgetDay {
            try XCTUnwrap(FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
                .entry(now: now, clock: clock))
        }
        XCTAssertTrue(try snapshot(data).tasks.isEmpty)
        XCTAssertEqual(try snapshot(data).upcomingTasks, [])
        XCTAssertEqual(try snapshot(data).undated?.tasks.map(\.id), [task.id])
        let completedFromUndated = try XCTUnwrap(FlowWidgetTaskAction.complete(task.id, occurrenceDay: anchor,
                                                                               data: data, now: now, clock: clock))
        XCTAssertEqual(try snapshot(completedFromUndated).undated?.remaining, 0)
        XCTAssertTrue(data.setPlannedToday(task.id, enabled: true, now: now, clock: clock))
        XCTAssertEqual(try snapshot(data).tasks.map(\.id), [task.id])
        XCTAssertTrue(data.resolve(task.id, outcome: .failed, now: now, clock: clock))
        XCTAssertFalse(data.resolve(task.id, outcome: .failed, now: now, clock: clock))
        XCTAssertEqual(data.tasks.first?.day, anchor)
        var completed = try XCTUnwrap(FlowWidgetTaskAction.complete(task.id, occurrenceDay: anchor, data: data,
                                                                    now: now, clock: clock))
        let record = try XCTUnwrap(completed.history.last)
        XCTAssertFalse(record.hasDeadline)
        XCTAssertTrue(completed.undoCompletion(record.id, now: now, clock: clock))
        XCTAssertEqual(completed.tasks, data.tasks)
        XCTAssertTrue(completed.changeDeadline(task.id, to: clock.today(now), clock: clock))
        XCTAssertEqual(completed.tasks.first?.hasDeadline, true)
    }

    func testUndatedWidgetShowsOnlySevenUndatedTitlesAndHidesPrivateNames() throws {
        let now = date("2026-11-16T20:00:00")
        let today = clock.today(now)
        let noDeadline = (1...8).map { FlowTask(title: "Undated \($0)", day: today, noDeadline: true) }
        let data = FlowData(tasks: noDeadline + [FlowTask(title: "Due today", day: today)])
        let snapshot = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        XCTAssertEqual(snapshot.days.first?.undated?.remaining, 8)
        XCTAssertEqual(snapshot.days.first?.undated?.tasks.map(\.title), Array(noDeadline.prefix(7)).map(\.title))
        let hidden = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: false)
        XCTAssertEqual(hidden.days.first?.undated?.remaining, 8)
        XCTAssertEqual(hidden.days.first?.undated?.tasks, [])
    }

    func testWidgetRoutingAndAltStoreGroupNames() {
        let id = UUID()
        XCTAssertEqual(FlowWidgetRoute(FlowWidgetRoute.url(for: id))?.taskID, id)
        XCTAssertNotNil(FlowWidgetRoute(FlowWidgetRoute.url()))
        XCTAssertNil(FlowWidgetRoute(URL(string: "lifeflow://todo/wrong")!))
        let day = date("2026-11-16T00:00:00")
        let displayed = date("2026-11-15T00:00:00")
        let completion = FlowWidgetRoute(FlowWidgetRoute.completionURL(for: id, occurrenceDay: day, displayedDay: displayed))
        XCTAssertEqual(completion?.taskID, id)
        XCTAssertEqual(completion?.occurrenceDay, day)
        XCTAssertEqual(completion?.displayedDay, displayed)
        XCTAssertNil(FlowWidgetRoute(URL(string: "lifeflow://todo/complete/\(id.uuidString)")!))
        let legacy = "lifeflow://todo/complete/\(id.uuidString)?day=\(day.timeIntervalSince1970)"
        XCTAssertEqual(FlowWidgetRoute(URL(string: legacy)!)?.occurrenceDay, day)
        XCTAssertNil(FlowWidgetRoute(URL(string: legacy + "&shown=nan")!))
        let base = FlowWidgetContainer.identifier
        XCTAssertEqual(FlowWidgetContainer.groupIDs(["group.other", base + ".TEAM"]), [base + ".TEAM", base])
    }

    func testWidgetSnapshotProvidesNamesForSmallAndMediumAndRespectsPrivacy() throws {
        let now = date("2026-11-16T20:00:00")
        let tasks = (1...4).map { FlowTask(title: "表示するタスク \($0)", day: clock.today(now)) }
        let data = FlowData(tasks: tasks)

        let visible = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: true)
        let today = try XCTUnwrap(visible.entry(now: now, clock: clock))
        XCTAssertEqual(today.tasks.map(\.title), ["表示するタスク 1", "表示するタスク 2", "表示するタスク 3", "表示するタスク 4"])
        XCTAssertEqual(today.tasks.first?.occurrenceDay, clock.today(now))

        let hidden = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: false)
        let hiddenToday = try XCTUnwrap(hidden.entry(now: now, clock: clock))
        XCTAssertEqual(hiddenToday.remaining, 4)
        XCTAssertTrue(hiddenToday.tasks.isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self)
        XCTAssertFalse(encoded.contains("表示するタスク"))
    }
}
