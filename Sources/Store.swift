import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
@MainActor final class FlowStore: ObservableObject {
    @Published private(set) var data = FlowData()
    @Published var error: String?
    @Published private(set) var ready = false
    @Published private(set) var undo = FlowUndo()
    let clock = FlowClock()
    let reminders = FlowReminders()
    private let url: URL
    private var needsMigrationCopy = false
    private static let maxDataBytes = 20 * 1024 * 1024
    private static let maxCarriesPerWrite = 10_000
    private struct SchemaHeader: Decodable { let schemaVersion: Int }
    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LifeFlow", isDirectory: true).appendingPathComponent("lifeflow.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-lifeflow-preview") {
                let today = clock.today()
                data = FlowData(tasks: [
                    FlowTask(title: "今日の予定を確認する", note: "まず大事なことから", day: today, favorite: true, priority: .high, category: "仕事", subtasks: [FlowSubtask(title: "予定を確認", isDone: true), FlowSubtask(title: "資料を用意")]),
                    FlowTask(title: "部屋を片付ける", day: today, category: "生活"),
                    FlowTask(title: "買い物リストをまとめる", day: clock.calendar.date(byAdding: .day, value: 1, to: today)!, priority: .low)
                ])
                ready = true
                return
            }
            #endif
            if FileManager.default.fileExists(atPath: url.path) {
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maxDataBytes {
                    throw FlowError.invalidBackup
                }
                let bytes = try Data(contentsOf: url)
                data = try Self.decode(bytes)
                needsMigrationCopy = try JSONDecoder().decode(SchemaHeader.self, from: bytes).schemaVersion < FlowData.currentSchema
            }
            ready = true
            roll()
            reminders.update(data.tasks)
        } catch { self.error = "保存データを読み込めません。元ファイルを保護しています。バックアップから復元してください。\n\(error.localizedDescription)" }
    }
    static func encode(_ value: FlowData) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(value)
    }
    static func decode(_ bytes: Data) throws -> FlowData {
        guard bytes.count <= Self.maxDataBytes else { throw FlowError.invalidBackup }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(FlowData.self, from: bytes).validated()
    }
    @discardableResult private func commit(_ candidate: FlowData, restoring: Bool = false) -> Bool {
        guard ready || restoring else { return false }
        do {
            let validated = try candidate.validated()
            let bytes = try Self.encode(validated)
            guard bytes.count <= Self.maxDataBytes else { throw FlowError.invalidBackup }
            if (restoring || needsMigrationCopy) && FileManager.default.fileExists(atPath: url.path) {
                let prefix = restoring ? "before-restore" : "before-migration"
                let safety = url.deletingLastPathComponent().appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: safety)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: safety.path)
            }
            try bytes.write(to: url, options: [.atomic, .completeFileProtection])
            needsMigrationCopy = false
            data = validated; ready = true; error = nil
            undo.clear()
            reminders.update(data.tasks)
            return true
        } catch { self.error = "保存できませんでした。変更は反映していません。\n\(error.localizedDescription)"; return false }
    }
    func roll() {
        guard ready else { return }
        if undo.label != nil && undo.candidate(now: Date(), clock: clock) == nil { undo.clear() }
        var next = data
        guard next.rollover(now: Date(), clock: clock, maxCarries: Self.maxCarriesPerWrite) else {
            error = "古い予定が多いため自動繰り越しを停止しました。元データは保存されています。"
            return
        }
        if next.tasks != data.tasks { commit(next) }
    }
    @discardableResult func save(_ task: FlowTask) -> Bool {
        var next = data
        if let i = next.tasks.firstIndex(where: { $0.id == task.id }) { next.tasks[i] = task }
        else { next.tasks.append(task) }
        guard next.rollover(now: Date(), clock: clock, maxCarries: Self.maxCarriesPerWrite) else {
            error = "一度に繰り越せる件数を超えたため保存できません。予定日を確認してください。"
            return false
        }
        return commit(next)
    }
    func resolve(_ task: FlowTask, _ outcome: Outcome) {
        roll()
        // Ignore a stale row/double tap, including one whose next repeat is already scheduled.
        guard data.tasks.first(where: { $0.id == task.id }) == task else { return }
        let now = Date()
        let previous = data
        var next = data; next.resolve(task.id, outcome: outcome, now: now, clock: clock)
        guard next.tasks != previous.tasks || next.history.count != previous.history.count else { return }
        if commit(next) {
            let label = outcome == .completed ? "達成" : outcome == .failed ? "失敗" : "削除"
            undo.remember(previous, label: label, now: now, clock: clock)
        }
    }
    func undoLast() {
        guard let previous = undo.candidate(now: Date(), clock: clock) else { undo.clear(); return }
        commit(previous)
    }
    func star(_ task: FlowTask) {
        guard let current = data.tasks.first(where: { $0.id == task.id }) else { return }
        var next = current; next.favorite.toggle(); save(next)
    }
    func restore(_ bytes: Data) throws {
        var next = try Self.decode(bytes)
        guard next.rollover(now: Date(), clock: clock, maxCarries: Self.maxCarriesPerWrite) else { throw FlowError.invalidBackup }
        commit(next, restoring: true)
    }
    func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        guard ready else { return }
        roll()
        var next = data
        if next.toggleSubtask(taskID: taskID, subtaskID: subtaskID) { commit(next) }
    }
    func saveCategoryButtons(_ names: [String]) -> Bool {
        var next = data; next.categoryButtons = names
        return commit(next)
    }
    func saveGoal(_ goal: FlowGoal) -> Bool {
        var next = data
        if let index = next.annualGoals.firstIndex(where: { $0.id == goal.id }) {
            next.annualGoals[index] = goal
        } else {
            next.annualGoals.append(goal)
        }
        return commit(next)
    }

    func deleteGoal(_ id: UUID) -> Bool {
        var next = data
        next.annualGoals.removeAll { $0.id == id }
        return commit(next)
    }

    func addGoalStepToToday(_ stepID: UUID, goalID: UUID) -> Bool {
        guard let task = data.todoForGoalStep(stepID, goalID: goalID, today: clock.today()) else { return false }
        return save(task)
    }

    func restHabit(_ id: UUID) {
        let now = Date()
        let previous = data
        var next = data
        if next.markHabit(id, outcome: .rest, now: now, clock: clock), commit(next) {
            undo.remember(previous, label: "休養日の記録", now: now, clock: clock)
        }
    }
}
