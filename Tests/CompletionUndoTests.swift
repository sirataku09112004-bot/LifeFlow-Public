import XCTest
@testable import LifeFlowCore

final class CompletionUndoTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testUndoAfterReloadForOneOffRepeatAndHabit() throws {
        let now = date("2026-11-13T12:00:00")
        let today = clock.today(now)
        for type in 0..<3 {
            let task = FlowTask(title: "記録", note: "元のメモ", day: today, favorite: true,
                                originDay: date("2026-11-12T00:00:00"),
                                repeatRule: type == 1 ? .daily : nil, category: "生活",
                                subtasks: [FlowSubtask(title: "準備", isDone: true)], habitGoal: type == 2 ? 3 : nil)
            let other = FlowTask(title: "別のタスク", day: today)
            var data = FlowData(tasks: [task, other])
            XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
            let event = try XCTUnwrap(data.history.last)
            for _ in 0..<25 {
                XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
            }
            XCTAssertTrue(data.resolve(other.id, outcome: .completed, now: now, clock: clock))

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
            XCTAssertTrue(data.canUndoCompletion(event.id, now: now, clock: clock))
            XCTAssertTrue(data.undoCompletion(event.id, now: now, clock: clock))
            XCTAssertFalse(data.undoCompletion(event.id, now: now, clock: clock))
            XCTAssertEqual(data.tasks, [task])
            XCTAssertEqual(data.history.map(\.taskID), [other.id])
            XCTAssertTrue(data.habitDays.isEmpty)

            data = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
            XCTAssertEqual(data.tasks, [task])
            XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
            XCTAssertFalse(data.undoCompletion(event.id, now: now, clock: clock))
            XCTAssertEqual(data.history.filter { $0.taskID == task.id }.count, 1)
            XCTAssertEqual(data.habitDays.count, type == 2 ? 1 : 0)
        }
    }

    func testUndoDoesNotOverwriteEditedNextOccurrenceOrCrossFourAM() throws {
        let now = date("2026-11-13T12:00:00")
        let task = FlowTask(title: "毎日", day: clock.today(now), repeatRule: .daily)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        let event = try XCTUnwrap(data.history.last)
        XCTAssertTrue(data.canUndoCompletion(event.id, now: date("2026-11-14T03:59:59"), clock: clock))
        XCTAssertFalse(data.undoCompletion(event.id, now: date("2026-11-14T04:00:00"), clock: clock))
        data.tasks[0].note = "新しいメモ"
        XCTAssertFalse(data.undoCompletion(event.id, now: now, clock: clock))
        XCTAssertEqual(data.tasks[0].note, "新しいメモ")
        XCTAssertEqual(data.history.count, 1)
    }

    func testOldCompletionIsVisibleWithoutUndoForV08ThroughV091() throws {
        let now = date("2026-11-13T12:00:00")
        for schema in [4, 5] {
            let json = """
            {"schemaVersion":\(schema),"tasks":[],"history":[{
              "id":"00000000-0000-0000-0000-000000000001","taskID":"00000000-0000-0000-0000-000000000002",
              "title":"旧記録","day":"2026-11-13T00:00:00+09:00","recordedAt":"2026-11-13T11:00:00+09:00","outcome":"completed"
            }]}
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var data = try decoder.decode(FlowData.self, from: Data(json.utf8)).validated()
            let event = try XCTUnwrap(data.completedToday(now: now, clock: clock).first)
            XCTAssertFalse(data.undoCompletion(event.id, now: now, clock: clock))
            XCTAssertEqual(data.history.count, 1)
        }
    }

    func testProgressAfterCompletionUndoAddDeleteCategoryAndFourAM() {
        let now = date("2026-11-13T12:00:00")
        let today = clock.today(now)
        let work = FlowTask(title: "仕事", day: today, category: "仕事")
        let personal = FlowTask(title: "私用", day: today, category: "生活")
        let future = FlowTask(title: "今後", day: date("2026-11-15T00:00:00"))
        var data = FlowData(tasks: [work, personal, future])
        func progress(_ at: Date, category: FlowCategoryFilter = .all) -> FlowTodayProgress {
            let pending = FlowTaskList(tasks: data.tasks, query: "", category: category, now: at, clock: clock).today
            let completed = data.completedToday(now: at, clock: clock, category: category)
            return FlowTodayProgress(data: data, pending: pending, completed: completed,
                                     now: at, clock: clock, category: category, favoritesOnly: false)
        }
        XCTAssertEqual(progress(now).total, 2)
        XCTAssertTrue(data.resolve(work.id, outcome: .completed, now: now, clock: clock))
        XCTAssertEqual(progress(now).percent, 50)
        XCTAssertEqual(progress(now, category: .named("仕事")).percent, 100)
        XCTAssertEqual(progress(now, category: .named("生活")).percent, 0)

        let added = FlowTask(title: "追加", day: today)
        data.tasks.append(added)
        XCTAssertEqual(progress(now).total, 3)
        XCTAssertTrue(data.resolve(added.id, outcome: .deleted, now: now, clock: clock))
        XCTAssertEqual(progress(now).total, 2)

        XCTAssertTrue(data.resolve(personal.id, outcome: .failed, now: now, clock: clock))
        XCTAssertEqual(progress(now).total, 2)
        XCTAssertEqual(progress(now).percent, 50)
        XCTAssertTrue(data.resolve(personal.id, outcome: .deleted, now: now, clock: clock))
        XCTAssertEqual(progress(now).percent, 100)

        XCTAssertEqual(progress(date("2026-11-14T03:59:59")).completed, 1)
        XCTAssertEqual(progress(date("2026-11-14T04:00:00")).total, 0)
        let completion = data.completedToday(now: now, clock: clock)[0]
        XCTAssertTrue(data.undoCompletion(completion.id, now: now, clock: clock))
        XCTAssertEqual(progress(now).total, 1)
        XCTAssertEqual(progress(now).percent, 0)
    }
}
