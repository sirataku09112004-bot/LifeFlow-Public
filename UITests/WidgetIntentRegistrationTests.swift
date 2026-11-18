#if canImport(AppIntentsTesting)
import AppIntentsTesting
import XCTest

final class WidgetIntentRegistrationTests: XCTestCase {
    @MainActor
    func testSystemCanRunWidgetCompletionIntent() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("App Intents Testing requires iOS 27.") }

        let app = XCUIApplication()
        app.launchEnvironment["LIFEFLOW_UI_TEST_STORE"] = UUID().uuidString
        app.launch()

        let definitions = IntentDefinitions(bundleIdentifier: "local.private.lifeflow")
        let completion = definitions.intents["CompleteWidgetTaskInBackgroundIntent"]
            .makeIntent(taskID: "", occurrenceStamp: "0", displayedStamp: "0")

        // An invalid task ID exercises system dispatch without completing a task.
        _ = try await completion.run()
    }
}
#endif
