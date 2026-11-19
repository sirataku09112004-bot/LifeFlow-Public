import AppIntents
import Foundation
import OSLog
import WidgetKit

@available(iOS 17.0, *)
struct CompleteWidgetTaskInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "ウィジェットのToDoを達成"
    static let isDiscoverable = false
    private static let logger = Logger(subsystem: "local.private.lifeflow", category: "WidgetCompletion")

    @Parameter(title: "タスクID") var taskID: String
    @Parameter(title: "予定日") var occurrenceStamp: String
    @Parameter(title: "表示日") var displayedStamp: String

    init() {}

    init(taskID: UUID, occurrenceDay: Date, displayedDay: Date) {
        self.taskID = taskID.uuidString
        occurrenceStamp = String(Int(occurrenceDay.timeIntervalSince1970))
        displayedStamp = String(Int(displayedDay.timeIntervalSince1970))
    }

    func perform() async throws -> some IntentResult {
        #if LIFEFLOW_WIDGET_EXTENSION
        Self.logger.error("Widget completion did not reach the host app")
        return .result()
        #else
        defer { WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind) }
        Self.logger.notice("Widget completion started in the host app")
        guard let id = UUID(uuidString: taskID),
              let occurrence = day(from: occurrenceStamp), let displayed = day(from: displayedStamp) else {
            Self.logger.error("Widget completion parameters were invalid")
            return .result()
        }
        guard let url = FlowWidgetContainer.dataFile else {
            Self.logger.error("Widget completion could not locate the shared container")
            return .result()
        }
        do {
            let saved = try FlowWidgetSharedDataFile.completeTask(id, occurrenceDay: occurrence,
                displayedDay: displayed, at: url, now: Date(), clock: FlowClock())
            Self.logger.notice("Widget completion saved: \(saved, privacy: .public)")
        } catch {
            Self.logger.error("Widget completion failed to read or write shared data")
        }
        return .result()
        #endif
    }

    #if !LIFEFLOW_WIDGET_EXTENSION
    private func day(from stamp: String) -> Date? {
        guard let seconds = Int(stamp) else { return nil }
        let result = Date(timeIntervalSince1970: TimeInterval(seconds))
        return (Date.distantPast...Date.distantFuture).contains(result) ? result : nil
    }
    #endif
}

// The widget supplies the button and the app's background process saves the result.
@available(iOS, unavailable)
extension CompleteWidgetTaskInAppIntent: ForegroundContinuableIntent {}
