import XCTest
@testable import LifeFlowCore

final class OrganizationTests: XCTestCase {
    let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "+09:00")! }
    func testSubtaskToggleIsSharedByBothListsAndDoesNotCompleteParent() {
        let a = FlowSubtask(title: "机を片付ける")
        let b = FlowSubtask(title: "床を掃除する")
        let parent = FlowTask(title: "掃除", day: date("2026-11-03T00:00:00"), subtasks: [a, b])
        var data = FlowData(tasks: [parent])
        XCTAssertTrue(data.toggleSubtask(taskID: parent.id, subtaskID: a.id))
        XCTAssertTrue(data.toggleSubtask(taskID: parent.id, subtaskID: b.id))
        XCTAssertEqual(data.tasks.count, 1)
        XCTAssertTrue(data.history.isEmpty)
        let lists = FlowTaskList(tasks: data.tasks, query: "机", now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(lists.today[0].completedSubtasks, 2)
        XCTAssertEqual(lists.all[0].completedSubtasks, 2)
        XCTAssertTrue(data.toggleSubtask(taskID: parent.id, subtaskID: a.id))
        XCTAssertEqual(data.tasks[0].completedSubtasks, 1)
        XCTAssertFalse(data.toggleSubtask(taskID: parent.id, subtaskID: UUID()))
    }
    func testCategoryNormalizationFilterAndSearchTogether() throws {
        let day = date("2026-11-03T00:00:00")
        let work = FlowTask(title: "準備", day: day, category: " 仕事 ", subtasks: [FlowSubtask(title: "資料作成")])
        let life = FlowTask(title: "資料を読む", day: day, category: "生活")
        let other = FlowTask(title: "資料", day: day)
        let data = try FlowData(tasks: [work, life, other]).validated()
        XCTAssertEqual(data.tasks[0].category, "仕事")
        XCTAssertEqual(FlowCategories.names([" 仕事 ", "仕事", "", nil, "生活"]), ["仕事", "生活"])
        let filtered = FlowTaskList(tasks: data.tasks, query: "資料", category: .named("仕事"), now: day, clock: clock)
        XCTAssertEqual(filtered.all.map(\.id), [work.id])
        let uncategorized = FlowTaskList(tasks: data.tasks, query: "", category: .uncategorized, now: day, clock: clock)
        XCTAssertEqual(uncategorized.all.map(\.id), [other.id])
    }
    func testRepeatResetsChecklistButRecordsCompletedSnapshot() {
        let item = FlowSubtask(title: "確認する", isDone: true)
        let task = FlowTask(title: "日課", day: date("2026-11-03T00:00:00"), repeatRule: .daily, category: "生活", subtasks: [item])
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .completed, now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].category, "生活")
        XCTAssertEqual(data.tasks[0].checklist[0].id, item.id)
        XCTAssertFalse(data.tasks[0].checklist[0].isDone)
        XCTAssertEqual(data.history[0].category, "生活")
        XCTAssertEqual(data.history[0].subtasks?.first?.isDone, true)
    }
    func testFailureAndRolloverPreservePartialProgress() {
        let items = [FlowSubtask(title: "一つ目", isDone: true), FlowSubtask(title: "二つ目")]
        let task = FlowTask(title: "作業", day: date("2026-11-03T00:00:00"), category: "仕事", subtasks: items)
        var data = FlowData(tasks: [task])
        data.resolve(task.id, outcome: .failed, now: date("2026-11-03T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].checklist, items)
        data.rollover(now: date("2026-11-06T12:00:00"), clock: clock)
        XCTAssertEqual(data.tasks[0].checklist, items)
        XCTAssertTrue(data.history.allSatisfy { $0.subtasks == items && $0.category == "仕事" })
    }
    func testBackupRoundTripAndSchemaTwoUpgrade() throws {
        let now = date("2026-11-03T12:00:00")
        let task = FlowTask(title: "テスト", day: clock.today(now), category: "趣味", subtasks: [FlowSubtask(title: "小さな作業", isDone: true)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FlowData.self, from: encoder.encode(FlowData(tasks: [task]))).validated()
        XCTAssertEqual(restored.tasks, [task])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(restored)) as? [String: Any])
        object["schemaVersion"] = 2
        var tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        tasks[0].removeValue(forKey: "category"); tasks[0].removeValue(forKey: "subtasks")
        object["tasks"] = tasks
        let legacy = try decoder.decode(FlowData.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        XCTAssertEqual(legacy.schemaVersion, 5)
        XCTAssertNil(legacy.tasks[0].category)
        XCTAssertTrue(legacy.tasks[0].checklist.isEmpty)
    }
    func testValidationRejectsBrokenChecklists() {
        let item = FlowSubtask(title: "一つ目")
        var task = FlowTask(title: "親", day: Date(), subtasks: [item, item])
        XCTAssertThrowsError(try FlowData(tasks: [task]).validated())
        task.checklist = [FlowSubtask(title: "  ")]
        XCTAssertThrowsError(try FlowData(tasks: [task]).validated())
        task.checklist = (0..<51).map { FlowSubtask(title: "\($0)") }
        XCTAssertThrowsError(try FlowData(tasks: [task]).validated())
        task.checklist = []; task.category = String(repeating: "あ", count: 41)
        XCTAssertThrowsError(try FlowData(tasks: [task]).validated())
    }
}
