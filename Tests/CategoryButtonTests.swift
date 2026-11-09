import XCTest
@testable import LifeFlowCore

final class CategoryButtonTests: XCTestCase {
    let clock = FlowClock(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "+09:00")! }
    func testRegistryPersistsOrderAndEmptyChoice() throws {
        var data = FlowData(categoryButtons: [" 趣味 ", "仕事", "生活"])
        data = try data.validated()
        XCTAssertEqual(data.registeredCategories, ["趣味", "仕事", "生活"])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FlowData.self, from: encoder.encode(data)).validated()
        XCTAssertEqual(restored.categoryButtons, data.categoryButtons)
        data.categoryButtons = []
        XCTAssertEqual(try data.validated().registeredCategories, [])
    }
    func testLegacyCategoriesSeedButtonsWithoutChangingTask() throws {
        let task = FlowTask(title: "作業", day: clock.today(), category: "仕事")
        var old = FlowData(schemaVersion: 3, tasks: [task])
        old.record(task, outcome: .failed, now: Date())
        var data = try old.validated()
        XCTAssertEqual(data.schemaVersion, 5)
        XCTAssertEqual(data.registeredCategories, ["仕事"])
        data.categoryButtons = []
        data = try data.validated()
        XCTAssertTrue(data.registeredCategories.isEmpty)
        XCTAssertEqual(data.tasks[0].category, "仕事")
        XCTAssertEqual(data.history[0].category, "仕事")
        XCTAssertTrue(FlowCategories.matches(data.tasks[0].category, filter: .named("仕事")))
    }
    func testRegistryLimitsAndDuplicates() {
        XCTAssertThrowsError(try FlowData(categoryButtons: ["仕事", " 仕事 "]).validated())
        XCTAssertThrowsError(try FlowData(categoryButtons: ["  "]).validated())
        XCTAssertThrowsError(try FlowData(categoryButtons: [String(repeating: "あ", count: 41)]).validated())
        XCTAssertThrowsError(try FlowData(categoryButtons: (0..<31).map { "\($0)" }).validated())
        XCTAssertNoThrow(try FlowData(categoryButtons: (0..<30).map { "\($0)" }).validated())
    }
    func testFourDigitDatesAndYearRollover() {
        let now = date("2026-11-03T12:00:00")
        XCTAssertEqual(clock.recognize("1105", now: now), date("2026-11-05T00:00:00"))
        XCTAssertEqual(clock.recognize("１２２５", now: now), date("2026-12-25T00:00:00"))
        XCTAssertEqual(clock.recognize("0101", now: now), date("2027-01-01T00:00:00"))
        XCTAssertEqual(clock.recognize("1103", now: now), date("2026-11-03T00:00:00"))
        XCTAssertEqual(clock.recognize("0229", now: date("2028-01-01T12:00:00")), date("2028-02-29T00:00:00"))
        XCTAssertNil(clock.recognize("0230", now: now))
        XCTAssertNil(clock.recognize("1301", now: now))
        XCTAssertNil(clock.recognize("0000", now: now))
        XCTAssertNil(clock.recognize("١١/٠٥", now: now))
    }
    func testFourDigitExtractionAndNumberBoundaries() {
        let now = date("2026-11-03T12:00:00")
        let title = clock.parseInput(title: "1105に買い物", note: "牛乳", now: now)
        XCTAssertEqual(title?.date, date("2026-11-05T00:00:00"))
        XCTAssertEqual(title?.title, "買い物")
        let note = clock.parseInput(title: "片付け", note: "１２２５までに終わらせる", now: now)
        XCTAssertEqual(note?.note, "終わらせる")
        XCTAssertEqual(note?.date, date("2026-12-25T00:00:00"))
        XCTAssertNil(clock.parseInput(title: "A1105B", note: "", now: now))
        XCTAssertNil(clock.parseInput(title: "01101234", note: "", now: now))
        XCTAssertNil(clock.parseInput(title: "2026年の記録", note: "", now: now))
    }
    func testCompactDatesUseFourAMBoundary() {
        XCTAssertEqual(clock.recognize("1231", now: date("2027-01-01T03:59:59")), date("2026-12-31T00:00:00"))
        XCTAssertEqual(clock.recognize("1231", now: date("2027-01-01T04:00:00")), date("2027-12-31T00:00:00"))
    }
}
