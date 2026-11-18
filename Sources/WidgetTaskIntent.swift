import AppIntents
import Foundation

typealias WidgetTaskCompletion = @MainActor @Sendable (UUID, Date, Date) -> Bool

@available(iOS 17.2, *)
struct CompleteWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "ToDoを達成"
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "タスクID") var taskID: String
    @Parameter(title: "予定日") var occurrenceDay: Date
    @Parameter(title: "ウィジェットの表示日") var displayedDay: Date
    @Dependency private var completeTask: WidgetTaskCompletion

    init() {}

    init(taskID: UUID, occurrenceDay: Date, displayedDay: Date) {
        self.taskID = taskID.uuidString
        self.occurrenceDay = occurrenceDay
        self.displayedDay = displayedDay
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        // Use the running app's store so the widget and app cannot write competing copies.
        _ = completeTask(id, occurrenceDay, displayedDay)
        return .result()
    }
}
