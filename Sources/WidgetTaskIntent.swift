import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct CompleteWidgetTaskInBackgroundIntent: AppIntent {
    static var title: LocalizedStringResource = "ウィジェットのToDoを達成"
    static var isDiscoverable = false

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    #endif

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
        defer { WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind) }
        guard let id = UUID(uuidString: taskID),
              let occurrence = day(from: occurrenceStamp), let displayed = day(from: displayedStamp),
              let url = FlowWidgetContainer.dataFile else {
            record("共有データを開けませんでした")
            return .result()
        }
        do {
            let saved = try FlowWidgetSharedDataFile.completeTask(id, occurrenceDay: occurrence,
                displayedDay: displayed, at: url, now: Date(), clock: FlowClock())
            record(saved ? "アプリを開かずに達成を保存しました" : "現在の予定と一致しませんでした")
        } catch {
            record("達成を保存できませんでした")
        }
        return .result()
    }

    private func day(from stamp: String) -> Date? {
        guard let seconds = Int(stamp) else { return nil }
        let result = Date(timeIntervalSince1970: TimeInterval(seconds))
        return (Date.distantPast...Date.distantFuture).contains(result) ? result : nil
    }

    private func record(_ message: String) {
        guard let url = FlowWidgetContainer.resultFile else { return }
        try? FlowWidgetSharedDataFile.writeData(
            JSONEncoder().encode(FlowWidgetActionReport(date: Date(), message: message)),
            to: url, sharedGroup: true
        )
    }
}
