import XCTest

final class CompletionTapTests: XCTestCase {
    private func launch(_ app: XCUIApplication) {
        continueAfterFailure = false
        app.launchEnvironment["LIFEFLOW_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
    }

    func testEmptyCheckboxCenterAndPaddingThenUndoAfterRelaunch() {
        let app = XCUIApplication()
        launch(app)
        let complete = app.buttons["complete:A Normal"]
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        XCTAssertTrue(complete.isEnabled)
        XCTAssertGreaterThanOrEqual(complete.frame.width, 44)
        XCTAssertGreaterThanOrEqual(complete.frame.height, 44)
        let count = app.staticTexts["today-progress-count"]
        XCTAssertEqual(count.label, "0 / 3件達成")

        // Tap the hollow center, rather than the painted outline.
        complete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(count.label, "1 / 3件達成")
        XCTAssertEqual(app.descendants(matching: .any)["today-progress-bar"].firstMatch.value as? String, "33%")
        XCTAssertFalse(app.navigationBars["ToDoを編集"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertEqual(count.label, "1 / 3件達成")
        let undo = reveal(app.buttons["undo:A Normal"], in: app)
        undo.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "0 / 3件達成")
        complete.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertEqual(count.label, "1 / 3件達成")
    }

    func testDailyCheckboxAndUndo() {
        checkRecurringTask("B Daily")
    }

    func testHabitCheckboxAndUndo() {
        checkRecurringTask("C Habit")
    }

    func testFutureCheckboxIsDisabled() {
        let app = XCUIApplication()
        launch(app)
        let future = app.buttons["complete:D Future"]
        for _ in 0..<4 where !future.exists { app.swipeUp() }
        XCTAssertTrue(future.exists)
        XCTAssertFalse(future.isEnabled)
        XCTAssertFalse(app.buttons["undo:D Future"].exists)
    }

    private func checkRecurringTask(_ title: String) {
        let app = XCUIApplication()
        launch(app)
        let complete = reveal(app.buttons["complete:" + title], in: app)
        XCTAssertTrue(complete.isEnabled)
        complete.tap()

        let undo = reveal(app.buttons["undo:" + title], in: app)
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        let reopened = reveal(app.buttons["complete:" + title], in: app, down: false)
        XCTAssertTrue(reopened.isEnabled)
        XCTAssertFalse(undo.exists)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true) -> XCUIElement {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return element }
            if down { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
        return element
    }
}
