import XCTest
@testable import LifeFlowCore

final class CompletionTests: XCTestCase {
    private let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    func testRapidCompletionOfOneOffTaskRecordsOnlyOnce() {
        let now = date("2026-11-12T20:00:00")
        let task = FlowTask(title: "提出", day: clock.today(now))
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        for tap in 1...30 {
            XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: now.addingTimeInterval(Double(tap) / 100), clock: clock))
        }
        XCTAssertTrue(data.tasks.isEmpty)
        XCTAssertEqual(data.completedToday(now: now, clock: clock).map(\.title), ["提出"])
        XCTAssertEqual(data.history.count, 1)
    }

    func testRapidDailyRepeatAndHabitCompletionCannotAdvanceBeforeFourAM() {
        let now = date("2026-11-12T20:00:00")
        let before = date("2026-11-13T03:59:59")
        let after = date("2026-11-13T04:00:00")
        for isHabit in [false, true] {
            let task = FlowTask(title: "毎日の記録", day: clock.today(now),
                                repeatRule: isHabit ? nil : .daily, habitGoal: isHabit ? 3 : nil)
            var data = FlowData(tasks: [task])
            XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
            for tap in 1...30 {
                XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: now.addingTimeInterval(Double(tap) / 100), clock: clock))
            }
            XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: before, clock: clock))
            XCTAssertFalse(data.resolve(task.id, outcome: .failed, now: before, clock: clock))
            XCTAssertEqual(data.history.count, 1)
            XCTAssertEqual(data.completedToday(now: before, clock: clock).map(\.taskID), [task.id])
            XCTAssertEqual(data.tasks.first?.day, clock.today(after))
            XCTAssertTrue(data.completedToday(now: after, clock: clock).isEmpty)
            XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: after, clock: clock))
            XCTAssertEqual(data.history.map(\.day), [clock.today(now), clock.today(after)])
            XCTAssertEqual(data.habitDays.count, isHabit ? 2 : 0)
        }
    }

    func testFutureOneOffCannotCompleteOrFailButCanDelete() {
        let now = date("2026-11-12T20:00:00")
        let task = FlowTask(title: "今後の予定", day: date("2026-11-13T00:00:00"))
        var data = FlowData(tasks: [task])
        XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        XCTAssertFalse(data.resolve(task.id, outcome: .failed, now: now, clock: clock))
        XCTAssertTrue(data.history.isEmpty)
        XCTAssertTrue(data.resolve(task.id, outcome: .deleted, now: now, clock: clock))
    }

    func testMovingNextOccurrenceBackTodayCannotCompleteAgain() {
        let now = date("2026-11-12T20:00:00")
        let today = clock.today(now)
        let task = FlowTask(title: "毎日", day: today, repeatRule: .daily)
        var data = FlowData(tasks: [task])
        XCTAssertTrue(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        data.tasks[0].day = today
        XCTAssertFalse(data.resolve(task.id, outcome: .completed, now: now, clock: clock))
        XCTAssertEqual(data.history.count, 1)
    }

    func testCompletedSectionSurvivesEncodingAndRespectsFilters() throws {
        let now = date("2026-11-12T20:00:00")
        let today = clock.today(now)
        let starred = FlowTask(title: "読書", day: today, favorite: true, category: "趣味")
        let ordinary = FlowTask(title: "買い物", day: today)
        var data = FlowData(tasks: [starred, ordinary])
        XCTAssertTrue(data.resolve(starred.id, outcome: .completed, now: now, clock: clock))
        XCTAssertTrue(data.resolve(ordinary.id, outcome: .completed, now: now, clock: clock))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
        XCTAssertTrue(restored.tasks.isEmpty)
        XCTAssertEqual(Set(restored.completedToday(now: now, clock: clock).map(\.taskID)), Set([starred.id, ordinary.id]))
        XCTAssertEqual(restored.completedToday(now: now, clock: clock, category: .named("趣味")).map(\.taskID), [starred.id])
        XCTAssertEqual(restored.completedToday(now: now, clock: clock, favoritesOnly: true).map(\.taskID), [starred.id])
    }

    func testV08AndV09HistoryWithoutFavoriteFieldRemainsReadable() throws {
        let now = date("2026-11-12T20:00:00")
        for version in [4, 5] {
            let json = """
            {"schemaVersion":\(version),"tasks":[],"history":[{
              "id":"00000000-0000-0000-0000-000000000001","taskID":"00000000-0000-0000-0000-000000000002",
              "title":"旧記録","day":"2026-11-12T00:00:00+09:00","recordedAt":"2026-11-12T19:00:00+09:00",
              "outcome":"completed","category":"仕事"
            }]}
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try decoder.decode(FlowData.self, from: Data(json.utf8)).validated()
            XCTAssertEqual(data.schemaVersion, 5)
            XCTAssertNil(data.history.first?.favorite)
            XCTAssertEqual(data.completedToday(now: now, clock: clock, category: .named("仕事")).map(\.title), ["旧記録"])
        }
    }
}
