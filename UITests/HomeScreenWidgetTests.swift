import XCTest

final class HomeScreenWidgetTests: XCTestCase {
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
        tap(home.cells["LifeFlow検証"].firstMatch)
        tap(home.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch)
        tap(home.buttons["Done"])

        let tile = home.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "LifeFlow検証", "Widget")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "The Home Screen did not add the LifeFlow widget.")
        XCTAssertLessThan(tile.frame.width, tile.frame.height * 1.5, "Expected the small widget.")
        let taskLabel = tile.staticTexts[taskName].firstMatch
        XCTAssertTrue(taskLabel.waitForExistence(timeout: 30), "The test task did not appear in the widget.")
        tap(tile.descendants(matching: .any).matching(identifier: "widget-complete-task").firstMatch)

        XCTAssertTrue(tile.staticTexts["今日のタスクはありません"].firstMatch.waitForExistence(timeout: 25),
                      "The widget did not reflect the saved completion.")
        XCTAssertEqual(home.state, .runningForeground)
        XCTAssertNotEqual(app.state, .runningForeground)
        tap(tile.descendants(matching: .any).matching(identifier: "widget-registration-probe").firstMatch)
        app.activate()
        XCTAssertTrue(app.buttons["undo:\(taskName)"].waitForExistence(timeout: 15),
                      "The app did not load the completion saved by the widget.")
        tap(app.buttons["設定"])
        tap(app.buttons["ウィジェット設定"])
        tap(app.buttons["最後のウィジェット操作"])
        let diagnostic = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "iOSから操作診断を実行できました")).firstMatch
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 15), "The test action was not delivered from the widget.")
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Missing element: \(element)")
        element.tap()
    }
}
