import XCTest
@testable import LifeFlowCore

final class FlowTests: XCTestCase {
    let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "+09:00")! }
    func testFourAMBoundary() {
        XCTAssertEqual(clock.today(date("2026-10-23T03:59:59")), date("2026-10-22T00:00:00"))
        XCTAssertEqual(clock.today(date("2026-10-23T04:00:00")), date("2026-10-23T00:00:00"))
    }
    func testFridayFailureAndIdempotentRollover() {
        let friday = date("2026-10-23T00:00:00")
        let task = FlowTask(title: "買い物", day: friday)
        var value = FlowData(tasks: [task])
        value.resolve(task.id, outcome: .failed, now: date("2026-10-23T12:00:00"), clock: clock)
        XCTAssertEqual(value.tasks.first?.day, date("2026-10-26T00:00:00"))
        XCTAssertEqual(value.tasks.first?.originDay, friday)
        XCTAssertEqual(value.history.first?.outcome, .failed)
        value.rollover(now: date("2026-10-27T04:00:00"), clock: clock)
        let count = value.history.count
        value.rollover(now: date("2026-10-27T04:00:00"), clock: clock)
        XCTAssertEqual(value.history.count, count)
        XCTAssertEqual(value.tasks.first?.originDay, friday)
    }
    func testCompletionRemovesOnlyTargetAndPreservesSnapshot() {
        let task = FlowTask(title: "元タイトル", day: clock.today())
        var value = FlowData(tasks: [task, FlowTask(title: "別", day: clock.today())])
        value.resolve(task.id, outcome: .completed, now: Date(), clock: clock)
        XCTAssertEqual(value.tasks.count, 1)
        XCTAssertEqual(value.history.first?.title, "元タイトル")
    }
    func testNaturalDates() {
        let now = date("2026-10-22T12:00:00")
        XCTAssertEqual(clock.recognize("明日 買い物", now: now), date("2026-10-23T00:00:00"))
        XCTAssertEqual(clock.recognize("金曜日まで", now: now), date("2026-10-23T00:00:00"))
        XCTAssertEqual(clock.recognize("来週月曜日", now: now), date("2026-10-26T00:00:00"))
        XCTAssertEqual(clock.recognize("１０月２５日", now: now), date("2026-10-25T00:00:00"))
        XCTAssertEqual(clock.recognize("2027-01-02", now: now), date("2027-01-02T00:00:00"))
        XCTAssertNil(clock.recognize("2026-02-30", now: now))
        XCTAssertEqual(clock.recognize("明日", now: date("2026-10-23T03:00:00")), date("2026-10-23T00:00:00"))
    }
    func testBackupRoundTripAndVersionRejection() throws {
        let original = FlowData(tasks: [FlowTask(title: "テスト", day: clock.today())])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FlowData.self, from: encoder.encode(original)).validated()
        XCTAssertEqual(restored.tasks, original.tasks)
        var future = original; future.schemaVersion = 99
        XCTAssertThrowsError(try future.validated())
        var duplicates = original; duplicates.tasks.append(original.tasks[0])
        XCTAssertThrowsError(try duplicates.validated())
    }
    func testPeriodDeadlines() {
        let now = date("2026-11-01T12:00:00")
        for text in ["今年中に片付け", "年内に提出", "今年いっぱい", "年末まで"] {
            XCTAssertEqual(clock.recognize(text, now: now), date("2026-12-31T00:00:00"), text)
        }
        XCTAssertEqual(clock.recognize("来年中に旅行", now: now), date("2027-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("再来年末", now: now), date("2028-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("今月中に読書", now: now), date("2026-11-30T00:00:00"))
        XCTAssertEqual(clock.recognize("来月末まで", now: now), date("2026-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("再来月中", now: now), date("2027-01-31T00:00:00"))
        // Sunday belongs to the week that ends today; next week ends seven days later.
        XCTAssertEqual(clock.recognize("今週中", now: now), date("2026-11-01T00:00:00"))
        XCTAssertEqual(clock.recognize("来週中", now: now), date("2026-11-08T00:00:00"))
        XCTAssertEqual(clock.recognize("再来週末", now: now), date("2026-11-15T00:00:00"))
        XCTAssertEqual(clock.recognize("今週末", now: date("2026-11-02T12:00:00")), date("2026-11-08T00:00:00"))
    }
    func testPeriodBoundariesAndExplicitDatePriority() {
        XCTAssertEqual(clock.recognize("今年中", now: date("2027-01-01T03:59:59")), date("2026-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("今年中", now: date("2027-01-01T04:00:00")), date("2027-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("今月中", now: date("2026-11-01T03:00:00")), date("2026-10-31T00:00:00"))
        XCTAssertEqual(clock.recognize("来月中", now: date("2028-01-31T12:00:00")), date("2028-02-29T00:00:00"))
        XCTAssertEqual(clock.recognize("来月中", now: date("2027-01-31T12:00:00")), date("2027-02-28T00:00:00"))
        XCTAssertEqual(clock.recognize("今年中、2027年1月2日まで", now: date("2026-11-01T12:00:00")), date("2027-01-02T00:00:00"))
        XCTAssertNil(clock.recognize("2027年2月30日", now: date("2026-11-01T12:00:00")))
    }
    func testRelativeOffsets() {
        let now = date("2026-12-30T12:00:00")
        XCTAssertEqual(clock.recognize("３日後まで", now: now), date("2027-01-02T00:00:00"))
        XCTAssertEqual(clock.recognize("2週間後", now: now), date("2027-01-13T00:00:00"))
        XCTAssertEqual(clock.recognize("2か月後", now: now), date("2027-02-28T00:00:00"))
        XCTAssertEqual(clock.recognize("1年後", now: now), date("2027-12-30T00:00:00"))
        XCTAssertNil(clock.recognize("1000日後", now: now))
        XCTAssertNil(clock.recognize("1.5日後", now: now))
        XCTAssertNil(clock.recognize("期限を決めずに片付ける", now: now))
    }
    func testSearchAcrossTitleAndNote() {
        XCTAssertTrue(FlowSearch.matches("", title: "掃除"))
        XCTAssertTrue(FlowSearch.matches("掃除 台所", title: "今年中に掃除", note: "台所から始める"))
        XCTAssertFalse(FlowSearch.matches("掃除 旅行", title: "掃除", note: "台所"))
        XCTAssertTrue(FlowSearch.matches("abc", title: "ＡＢＣを読む"))
        XCTAssertTrue(FlowSearch.matches("\n  \t", title: "何でも"))
    }
    func testInsightsUseActionDayAndIgnoreRolloverAndDeletion() {
        let task = FlowTask(title: "古い予定", day: date("2026-10-20T00:00:00"))
        var data = FlowData()
        data.record(task, outcome: .completed, now: date("2026-11-02T03:59:00"))
        data.record(task, outcome: .failed, now: date("2026-11-02T04:00:00"))
        data.record(task, outcome: .carried, now: date("2026-11-02T05:00:00"))
        data.record(task, outcome: .deleted, now: date("2026-11-02T06:00:00"))
        let days = FlowInsights.days(history: data.history, count: 7, now: date("2026-11-02T12:00:00"), clock: clock)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].completed, 0)
        XCTAssertEqual(days[0].failed, 1)
        XCTAssertEqual(days[0].rate, 0)
        XCTAssertEqual(days[1].completed, 1)
        XCTAssertEqual(days[1].rate, 1)
        XCTAssertNil(days[2].rate)
        XCTAssertTrue(FlowInsights.days(history: [], count: 0, now: Date(), clock: clock).isEmpty)
    }
    func testInsightsCountRepeatedAttemptsAndExcludeOlderActions() {
        let task = FlowTask(title: "繰り返し", day: date("2026-11-01T00:00:00"))
        var data = FlowData()
        data.record(task, outcome: .completed, now: date("2026-10-01T12:00:00"))
        data.record(task, outcome: .failed, now: date("2026-11-01T10:00:00"))
        data.record(task, outcome: .completed, now: date("2026-11-01T12:00:00"))
        let days = FlowInsights.days(history: data.history, count: 30, now: date("2026-11-01T12:00:00"), clock: clock)
        XCTAssertEqual(days[0].attempts, 2)
        XCTAssertEqual(days[0].rate, 0.5)
        XCTAssertEqual(days.reduce(0) { $0 + $1.completed }, 1)
    }
    func testRemindersSkipPastAndRespectDueCalendarDate() {
        let tasks = [FlowTask(title: "昨日", day: date("2026-10-31T00:00:00")), FlowTask(title: "日曜日", day: date("2026-11-01T00:00:00")), FlowTask(title: "明日", day: date("2026-11-02T00:00:00"))]
        let before = FlowReminderPlan.make(tasks: tasks, hour: 9, now: date("2026-11-01T08:59:00"), clock: clock)
        XCTAssertEqual(before.map(\.title), ["日曜日", "明日"])
        XCTAssertEqual(before[0].fireDate, date("2026-11-01T09:00:00"))
        let after = FlowReminderPlan.make(tasks: tasks, hour: 9, now: date("2026-11-01T09:00:00"), clock: clock)
        XCTAssertEqual(after.map(\.title), ["明日"])
        XCTAssertTrue(FlowReminderPlan.make(tasks: tasks, hour: 3, now: Date(), clock: clock).isEmpty)
    }
    func testReminderLimitStableOrderingAndTaskRemoval() {
        let tasks = (0..<70).map { i in FlowTask(title: "\(i)", day: clock.calendar.date(byAdding: .day, value: i, to: date("2026-11-01T00:00:00"))!) }
        let now = date("2026-11-01T04:00:00")
        let plan = FlowReminderPlan.make(tasks: Array(tasks.reversed()), hour: 9, now: now, clock: clock)
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(plan.first?.title, "0")
        XCTAssertEqual(plan.last?.title, "59")
        let remaining = Array(tasks.dropFirst())
        let updated = FlowReminderPlan.make(tasks: remaining, hour: 9, now: now, clock: clock)
        XCTAssertFalse(updated.contains { $0.id == tasks[0].id })
        XCTAssertEqual(updated.first?.title, "1")
        XCTAssertEqual(updated.last?.title, "60")
    }
    func testDailyAndWeekdayRepeats() {
        let friday = date("2026-11-06T00:00:00")
        var task = FlowTask(title: "毎日", day: friday, favorite: true, repeatRule: .daily)
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .completed, now: date("2026-11-06T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks.first?.day, date("2026-11-07T00:00:00"))
        XCTAssertEqual(data.tasks.first?.id, task.id)
        XCTAssertEqual(data.tasks.first?.favorite, true)
        XCTAssertEqual(data.history.first?.outcome, .completed)
        task.repeatRule = .weekdays
        data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .completed, now: date("2026-11-06T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks.first?.day, date("2026-11-09T00:00:00"))
    }
    func testWeeklyRepeatRetainsOriginalWeekdayAfterFailure() {
        let task = FlowTask(title: "金曜の掃除", day: date("2026-11-06T00:00:00"), repeatRule: .weekly)
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .failed, now: date("2026-11-06T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].day, date("2026-11-09T00:00:00"))
        data.resolve(task.id, outcome: .completed, now: date("2026-11-09T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].day, date("2026-11-13T00:00:00"))
        XCTAssertNil(data.tasks[0].originDay)
        XCTAssertEqual(data.history.count, 2)
    }
    func testMonthlyRepeatClampsAndRestores31st() {
        let task = FlowTask(title: "月末の確認", day: date("2027-01-31T00:00:00"), repeatRule: .monthly)
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .completed, now: date("2027-01-31T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].day, date("2027-02-28T00:00:00"))
        data.resolve(task.id, outcome: .completed, now: date("2027-02-28T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].day, date("2027-03-31T00:00:00"))
        var leap = task; leap.day = date("2028-01-31T00:00:00")
        XCTAssertEqual(clock.nextOccurrence(for: leap, now: date("2028-01-31T12:00:00")), date("2028-02-29T00:00:00"))
    }
    func testRepeatDoesNotMultiplyOnRolloverAndDeletionStopsIt() {
        let task = FlowTask(title: "習慣", day: date("2026-11-02T00:00:00"), repeatRule: .daily)
        var data = FlowData(tasks: [task])
        data.rollover(now: date("2026-11-09T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks.count, 1)
        XCTAssertEqual(data.tasks[0].day, date("2026-11-09T00:00:00"))
        data.resolve(task.id, outcome: .completed, now: date("2026-11-09T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].day, date("2026-11-10T00:00:00"))
        data.resolve(task.id, outcome: .deleted, now: date("2026-11-09T13:00:00"), clock: clock)
        XCTAssertTrue(data.tasks.isEmpty)
    }
    func testOldJSONLoadsAndNewRepeatRoundTrips() throws {
        let id = UUID()
        let old = """
        {"schemaVersion":1,"tasks":[{"id":"\(id.uuidString)","title":"旧データ","note":"メモ","day":"2026-11-02T00:00:00+09:00","favorite":true}],"history":[]}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var restored = try decoder.decode(FlowData.self, from: Data(old.utf8)).validated()
        XCTAssertEqual(restored.schemaVersion, 5)
        XCTAssertEqual(restored.tasks[0].id, id)
        XCTAssertNil(restored.tasks[0].repeatRule)
        restored.tasks[0].repeatRule = .monthly
        restored.tasks[0].repeatAnchorDay = 31
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let roundTrip = try decoder.decode(FlowData.self, from: encoder.encode(restored)).validated()
        XCTAssertEqual(roundTrip.tasks, restored.tasks)
        restored.tasks[0].repeatAnchorDay = 32
        XCTAssertThrowsError(try restored.validated())
    }
    func testAutomaticDateExtractionCleansTitleAndMemo() {
        let now = date("2026-11-02T12:00:00")
        let title = clock.parseInput(title: "明日 買い物", note: "牛乳を買う", now: now)
        XCTAssertEqual(title?.date, date("2026-11-03T00:00:00"))
        XCTAssertEqual(title?.title, "買い物")
        XCTAssertEqual(title?.note, "牛乳を買う")
        XCTAssertEqual(title?.fromNote, false)
        let memo = clock.parseInput(title: "片付け", note: "今年中に机を片付ける", now: now)
        XCTAssertEqual(memo?.date, date("2026-12-31T00:00:00"))
        XCTAssertEqual(memo?.title, "片付け")
        XCTAssertEqual(memo?.note, "机を片付ける")
        XCTAssertEqual(memo?.fromNote, true)
        XCTAssertEqual(clock.parseInput(title: "明日の買い物", note: "", now: now)?.title, "買い物")
        XCTAssertEqual(clock.parseInput(title: "", note: "来週中までに提出", now: now)?.note, "提出")
    }
    func testExtractionPreservesOtherDatesAndInvalidInput() {
        let now = date("2026-11-02T12:00:00")
        let parsed = clock.parseInput(title: "明日 買い物", note: "来週中に整理", now: now)
        XCTAssertEqual(parsed?.date, date("2026-11-03T00:00:00"))
        XCTAssertEqual(parsed?.note, "来週中に整理")
        XCTAssertNil(clock.parseInput(title: "2027年2月30日に買う", note: "", now: now))
        XCTAssertNil(clock.parseInput(title: "買い物", note: "時間未定", now: now))
        let onlyDate = clock.parseInput(title: "明日", note: "", now: now)
        XCTAssertEqual(onlyDate?.title, "") // Editor must disable saving an empty cleaned title.
        let unicode = clock.parseInput(title: "📚 ２０２７／１／２に読む", note: "", now: now)
        XCTAssertEqual(unicode?.date, date("2027-01-02T00:00:00"))
        XCTAssertEqual(unicode?.title, "📚 読む")
    }
    func testCombinedTaskListUsesSameIDsAndGlobalSearch() {
        let today = date("2026-11-03T00:00:00")
        let a = FlowTask(title: "今日の掃除", day: today)
        let b = FlowTask(title: "未来の掃除", day: date("2026-11-04T00:00:00"), favorite: true)
        let c = FlowTask(title: "料理", day: today)
        let list = FlowTaskList(tasks: [c, b, a], query: "掃除", now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(list.today.map(\.id), [a.id])
        XCTAssertEqual(list.all.map(\.id), [a.id, b.id])
        XCTAssertEqual(list.favorites.map(\.id), [b.id])
        let removed = FlowTaskList(tasks: [c, b], query: "掃除", now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertTrue(removed.today.isEmpty)
        XCTAssertEqual(removed.all.map(\.id), [b.id])
    }
    func testPrioritySortKeepsDateFirstAndDefaultsToNormal() {
        let today = date("2026-11-03T00:00:00")
        let low = FlowTask(title: "低い", day: today, favorite: true, priority: .low)
        let normal = FlowTask(title: "通常", day: today)
        let high = FlowTask(title: "高い", day: today, priority: .high)
        let tomorrowHigh = FlowTask(title: "明日の高い", day: date("2026-11-04T00:00:00"), priority: .high)
        let list = FlowTaskList(tasks: [tomorrowHigh, low, normal, high], query: "", now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(list.all.map(\.id), [high.id, normal.id, low.id, tomorrowHigh.id])
        XCTAssertEqual(list.today.map(\.id), [high.id, normal.id, low.id])
    }
    func testPrioritySurvivesRepeatAndJSONRoundTrip() throws {
        let task = FlowTask(title: "継続", day: date("2026-11-03T00:00:00"), repeatRule: .daily, priority: .high)
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .completed, now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].priority, .high)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
        XCTAssertEqual(restored.tasks, data.tasks)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(data)) as? [String: Any])
        var tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        tasks[0].removeValue(forKey: "priority")
        object["tasks"] = tasks
        let legacy = try decoder.decode(FlowData.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        XCTAssertNil(legacy.tasks[0].priority)
    }
}

