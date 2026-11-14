import XCTest

final class PlanningUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LIFEFLOW_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
        return app
    }

    func testPlanTodayAndChangeDeadlineIndependently() {
        let app = launch()
        let count = app.staticTexts["today-progress-count"]
        XCTAssertEqual(count.label, "0 / 3件達成")
        let menu = app.buttons["schedule:D Future"]
        reveal(menu, in: app)
        menu.tap()
        app.buttons["今日やる予定に追加"].tap()
        reveal(count, in: app, down: false)
        XCTAssertEqual(count.label, "0 / 4件達成")
        XCTAssertEqual(app.buttons.matching(identifier: "complete:D Future").count, 1)

        reveal(menu, in: app)
        menu.tap()
        app.buttons["「今日やる」を解除"].tap()
        reveal(count, in: app, down: false)
        XCTAssertEqual(count.label, "0 / 3件達成")

        reveal(menu, in: app)
        menu.tap()
        app.buttons["今日"].tap()
        reveal(count, in: app, down: false)
        XCTAssertEqual(count.label, "0 / 4件達成")
    }

    func testReorderPersistsAcrossRelaunch() {
        let app = launch()
        app.buttons["today-reorder"].tap()
        let a = app.staticTexts["reorder:A Normal"]
        let b = app.staticTexts["reorder:B Daily"]
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        XCTAssertLessThan(a.frame.midY, b.frame.midY)
        let handle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Reorder A Normal")).firstMatch
        let start = handle.exists ? handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)) :
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 28, dy: a.frame.midY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 28, dy: b.frame.maxY + 4))
        start.press(forDuration: 0.25, thenDragTo: end)
        XCTAssertLessThan(b.frame.midY, a.frame.midY)
        app.buttons["完了"].tap()
        app.terminate()
        app.launch()
        XCTAssertLessThan(app.buttons["complete:B Daily"].frame.midY, app.buttons["complete:A Normal"].frame.midY)
    }

    func testPastHabitDayCanBeEdited() {
        let app = launch()
        app.buttons["習慣の記録"].firstMatch.tap()
        app.staticTexts["C Habit"].firstMatch.tap()
        let previous = app.buttons["前の期間"]
        reveal(previous, in: app)
        previous.tap()
        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit-day-")).firstMatch
        reveal(day, in: app)
        day.tap()
        app.buttons["達成"].tap()
        let status = app.staticTexts["habit-selected-record"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.hasSuffix("・達成"))
    }

    func testWidgetTaskLinkOpensToDoEditor() {
        guard #available(iOS 18.0, *) else { return }
        let app = launch()
        app.tabBars.buttons["年間目標"].tap()
        app.open(URL(string: "lifeflow://todo/EF6A4AF5-6253-4D4D-B67B-9DC9BFE33F50")!)
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(title.value as? String, "D Future")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if down { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
