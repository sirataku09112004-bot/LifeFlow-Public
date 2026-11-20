import XCTest

final class HomeScreenWidgetTests: XCTestCase {
    @MainActor
    func testUndatedWidgetShowsOnlyUndatedTasksAndCompletesInBackground() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("The Home Screen controls are for iOS 27.") }
        continueAfterFailure = false
        let app = XCUIApplication()
        let prefix = "Task \(UUID().uuidString.prefix(6))"
        let undatedNames = (1...8).map { "\(prefix) \($0)" }
        let datedName = "Dated sample \(UUID().uuidString.prefix(6))"
        app.launch()

        tap(app.buttons["ToDoを追加"])
        let title = app.textFields.firstMatch
        tap(title)
        title.typeText(datedName)
        tap(app.buttons["保存"])

        for name in undatedNames {
            tap(app.buttons["ToDoを追加"])
            let noDeadline = app.switches["期限なし"]
            XCTAssertTrue(noDeadline.waitForExistence(timeout: 8))
            noDeadline.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertEqual(noDeadline.value as? String, "1")
            tap(title)
            title.typeText(name)
            tap(app.buttons["保存"])
        }
        tap(app.buttons["設定"])
        tap(app.buttons["ウィジェット設定"])
        tap(app.buttons["ウィジェットにToDo名を表示"])

        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 2)
        tap(home.buttons["Edit"])
        tap(home.buttons["Add Widget"])
        let search = home.searchFields.firstMatch
        tap(search)
        search.typeText("LifeFlow")
        tap(home.cells["LifeFlow"].firstMatch)
        let preview = home.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND value == %@",
                                                        "やることリスト", "Widget, Small"))
        for _ in 0..<3 where !preview.allElementsBoundByIndex.contains(where: \.isHittable) {
            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.51))
            let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.51))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(preview.allElementsBoundByIndex.contains(where: \.isHittable), home.debugDescription)
        tap(home.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch)
        tap(home.buttons["Done"])

        let tile = home.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "LifeFlow", "Widget")).firstMatch
        let heading = tile.staticTexts["やることリスト"]
        XCTAssertTrue(heading.waitForExistence(timeout: 25))
        XCTAssertLessThan(tile.frame.width, tile.frame.height * 1.5)
        XCTAssertEqual(heading.frame.midX, tile.frame.midX, accuracy: 3)
        for name in undatedNames.prefix(7) {
            let row = tile.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 25))
            XCTAssertGreaterThanOrEqual(row.frame.minY, tile.frame.minY)
            XCTAssertLessThanOrEqual(row.frame.maxY, tile.frame.maxY)
        }
        XCTAssertFalse(tile.staticTexts[undatedNames[7]].exists)
        XCTAssertFalse(tile.staticTexts[datedName].exists)
        XCTAssertFalse(tile.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "残り")).firstMatch.exists)
        tap(tile.descendants(matching: .any).matching(identifier: "widget-complete-task").firstMatch)
        XCTAssertTrue(tile.staticTexts[undatedNames[7]].waitForExistence(timeout: 25))
        XCTAssertFalse(tile.staticTexts[undatedNames[0]].exists)
        XCTAssertEqual(home.state, .runningForeground)
        XCTAssertNotEqual(app.state, .runningForeground)
        app.activate()
        XCTAssertTrue(app.buttons["undo:\(undatedNames[0])"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["complete:\(datedName)"].exists)
    }

    @MainActor
    func testMediumWidgetShowsTodayAndUpcomingSideBySide() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("The Home Screen controls are for iOS 27.") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let taskName = "Upcoming \(UUID().uuidString.prefix(6))"
        let dueDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: Date()))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        tap(app.buttons["ToDoを追加"])
        let title = app.textFields.firstMatch
        tap(title)
        title.typeText(taskName + " " + formatter.string(from: dueDate))
        tap(app.buttons["保存"])
        tap(app.buttons["設定"])
        tap(app.buttons["ウィジェット設定"])
        tap(app.buttons["ウィジェットにToDo名を表示"])
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)

        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 2)
        tap(home.buttons["Edit"])
        tap(home.buttons["Add Widget"])
        let search = home.searchFields.firstMatch
        tap(search)
        search.typeText("LifeFlow")
        tap(home.cells["LifeFlow"].firstMatch)

        let preview = home.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND value == %@",
                                                        "今日のToDo", "Widget, Medium"))
        for _ in 0..<4 where !preview.allElementsBoundByIndex.contains(where: \.isHittable) {
            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.51))
            let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.51))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(preview.allElementsBoundByIndex.contains(where: \.isHittable), home.debugDescription)
        tap(home.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch)
        tap(home.buttons["Done"])

        let tile = home.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "LifeFlow", "Widget")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(tile.frame.width, tile.frame.height * 1.5)
        let today = tile.staticTexts["今日のToDo"].firstMatch
        let upcoming = tile.staticTexts["今後の予定"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        XCTAssertTrue(upcoming.waitForExistence(timeout: 20))
        XCTAssertLessThan(today.frame.midX, upcoming.frame.midX)
        XCTAssertEqual(today.frame.midY, upcoming.frame.midY, accuracy: 2)
        XCTAssertEqual(today.frame.midX, tile.frame.minX + tile.frame.width / 4, accuracy: 12)
        XCTAssertEqual(upcoming.frame.midX, tile.frame.maxX - tile.frame.width / 4, accuracy: 12)
        let taskLabel = tile.descendants(matching: .any).matching(identifier: "widget-upcoming-task:" + taskName).firstMatch
        XCTAssertTrue(taskLabel.waitForExistence(timeout: 25))
        let complete = tile.descendants(matching: .any).matching(identifier: "widget-complete-upcoming-task").firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(complete.frame.midX, taskLabel.frame.midX)
        tap(complete)
        XCTAssertTrue(tile.staticTexts["今後の予定はありません"].waitForExistence(timeout: 25))
        XCTAssertEqual(home.state, .runningForeground)
        XCTAssertNotEqual(app.state, .runningForeground)
        tile.press(forDuration: 1.5)
        tap(home.buttons["Remove Widget"])
        tap(home.buttons["Remove"])
        app.activate()
        XCTAssertTrue(app.buttons["undo:\(taskName)"].waitForExistence(timeout: 15))
        tap(app.buttons["設定"])
        tap(app.buttons["ウィジェット設定"])
        tap(app.buttons["ウィジェットにToDo名を表示"])
    }

    @MainActor
    func testSmallWidgetCompletesToDoWithoutOpeningLifeFlow() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("The Home Screen controls are for iOS 27.") }
        continueAfterFailure = false
        let app = XCUIApplication()
        let taskName = "Widget check \(UUID().uuidString.prefix(6))"
        app.launch()

        tap(app.buttons["ToDoを追加"])
        let title = app.textFields.firstMatch
        tap(title)
        title.typeText(taskName)
        tap(app.buttons["保存"])
        XCTAssertTrue(app.buttons["complete:\(taskName)"].waitForExistence(timeout: 10))

        tap(app.buttons["設定"])
        tap(app.buttons["ウィジェット設定"])
        tap(app.buttons["ウィジェットにToDo名を表示"])

        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 2)
        tap(home.buttons["Edit"])
        tap(home.buttons["Add Widget"])
        let search = home.searchFields.firstMatch
        tap(search)
        search.typeText("LifeFlow")
        tap(home.cells["LifeFlow"].firstMatch)
        tap(home.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch)
        tap(home.buttons["Done"])

        let tile = home.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "LifeFlow", "Widget")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "The Home Screen did not add the LifeFlow widget.")
        XCTAssertLessThan(tile.frame.width, tile.frame.height * 1.5, "Expected the small widget.")
        let taskLabel = tile.staticTexts[taskName].firstMatch
        XCTAssertTrue(taskLabel.waitForExistence(timeout: 30), "The test task did not appear in the widget.")
        tap(tile.descendants(matching: .any).matching(identifier: "widget-complete-task").firstMatch)

        XCTAssertTrue(tile.staticTexts["今日のタスクはありません"].firstMatch.waitForExistence(timeout: 25),
                      "The widget did not reflect the saved completion.")
        XCTAssertEqual(home.state, .runningForeground)
        XCTAssertNotEqual(app.state, .runningForeground)
        app.activate()
        XCTAssertTrue(app.buttons["undo:\(taskName)"].waitForExistence(timeout: 15),
                      "The app did not load the completion saved by the widget.")
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Missing element: \(element)")
        element.tap()
    }
}
