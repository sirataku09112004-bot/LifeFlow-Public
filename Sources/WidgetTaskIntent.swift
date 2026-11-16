import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct CompleteWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "ToDoを達成"
    static var openAppWhenRun = false

    @Parameter(title: "タスクID") var taskID: String
    @Parameter(title: "予定日") var occurrenceDay: Date

    init() {
        taskID = ""
        occurrenceDay = .distantPast
    }

    init(taskID: UUID, occurrenceDay: Date) {
        self.taskID = taskID.uuidString
        self.occurrenceDay = occurrenceDay
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID), let dataURL = FlowWidgetContainer.dataFile else {
            throw WidgetTaskIntentError.sharedDataUnavailable
        }
        let now = Date()
        let clock = FlowClock()
        let data = try FlowWidgetSharedDataFile.read(from: dataURL)
        guard let completed = FlowWidgetTaskAction.complete(id, occurrenceDay: occurrenceDay,
                                                            data: data, now: now, clock: clock) else {
            WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind)
            return .result()
        }
        try FlowWidgetSharedDataFile.write(completed, to: dataURL, sharedGroup: true)

        if let snapshotURL = FlowWidgetContainer.file {
            let oldBytes = try? FlowWidgetSharedDataFile.readData(from: snapshotURL)
            let oldSnapshot = oldBytes.flatMap { try? JSONDecoder().decode(FlowWidgetSnapshot.self, from: $0) }
            let showTitles = oldSnapshot?.entry(now: now, clock: clock)?.titlesVisible ?? false
            let snapshot = FlowWidgetSnapshot(data: completed, now: now, clock: clock, showTitles: showTitles)
            if let bytes = try? JSONEncoder().encode(snapshot) {
                try? FlowWidgetSharedDataFile.writeData(bytes, to: snapshotURL, sharedGroup: true)
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind)
        return .result()
    }
}

private enum WidgetTaskIntentError: LocalizedError {
    case sharedDataUnavailable

    var errorDescription: String? {
        "共有データを開けませんでした。LifeFlowを一度開いてから、もう一度お試しください。"
    }
}
