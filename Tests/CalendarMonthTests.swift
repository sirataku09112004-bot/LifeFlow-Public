import XCTest
@testable import LifeFlowCore

final class CalendarMonthTests: XCTestCase {
    func testDeadlineAndPlanAppearOnTheirOwnDatesAndSameDayDoesNotDuplicate() throws {
        let clock = FlowClock(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let start = try XCTUnwrap(clock.calendar.date(from: DateComponents(year: 2028, month: 2, day: 1)))
        let deadline = try XCTUnwrap(clock.calendar.date(byAdding: .day, value: 28, to: start))
        let nextMonth = try XCTUnwrap(clock.calendar.date(byAdding: .month, value: 1, to: start))
        let split = FlowTask(title: "締切と予定", day: nextMonth, originDay: deadline, plannedDay: start)
        let same = FlowTask(title: "同じ日の締切と予定", day: deadline, plannedDay: deadline)
        let outside = FlowTask(title: "来月の締切", day: nextMonth)
        let month = FlowCalendarMonth(containing: deadline, tasks: [split, same, outside], clock: clock)

        XCTAssertEqual(month.days.count, 29)
        XCTAssertEqual(month.leadingDays, 2)
        XCTAssertEqual(month.days.last, deadline)
        XCTAssertEqual(month.itemsByDay[start]?.map(\.id), [split.id])
        XCTAssertEqual(month.itemsByDay[start]?.first?.isDeadline, false)
        XCTAssertEqual(month.itemsByDay[start]?.first?.isPlanned, true)
        let lastDayItems = try XCTUnwrap(month.itemsByDay[deadline])
        XCTAssertEqual(Set(lastDayItems.map(\.id)), Set([split.id, same.id]))
        XCTAssertEqual(lastDayItems.count, 2)
        XCTAssertTrue(lastDayItems.allSatisfy(\.isDeadline))
        XCTAssertEqual(lastDayItems.filter(\.isPlanned).map(\.id), [same.id])
        XCTAssertNil(month.itemsByDay[nextMonth])
    }
}
