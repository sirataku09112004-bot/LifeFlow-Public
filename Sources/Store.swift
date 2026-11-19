import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

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
    @Published private(set) var widgetShowsTitles = UserDefaults.standard.bool(forKey: "widgetShowsTitles")
    @Published private(set) var widgetOpensForCompletion = UserDefaults.standard.bool(forKey: "widgetOpensForCompletion")
    private var lastAppWidgetAction: FlowWidgetActionReport?
    var lastWidgetAction: String? {
        var latest = lastAppWidgetAction
        if let url = FlowWidgetContainer.resultFile,
           let bytes = try? FlowWidgetSharedDataFile.readData(from: url),
           let report = try? JSONDecoder().decode(FlowWidgetActionReport.self, from: bytes),
           latest.map({ $0.date < report.date }) ?? true {
            latest = report
        }
        return latest.map { $0.date.formatted(date: .abbreviated, time: .standard) + "  " + $0.message }
    }
    var widgetDiagnostics: String {
        let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("LifeFlowWidget.appex")
        func actionStatus(in bundleURL: URL?) -> String {
            let metadata = bundleURL?.appendingPathComponent("Metadata.appintents/extract.actionsdata")
            let actions = metadata.flatMap { try? Data(contentsOf: $0) }.flatMap {
                (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["actions"] as? [String: Any]
            }
            return actions?["CompleteWidgetTaskInAppIntent"] == nil ? "見つかりません" : "あり"
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
        return [
            "ビルド \(build)",
            "操作定義　アプリ \(actionStatus(in: Bundle.main.bundleURL)) ／ ウィジェット \(actionStatus(in: extensionURL))",
            "共有データ領域 \(widgetEnabled ? "利用可" : "利用不可")",
            lastWidgetAction ?? "ウィジェットから受け取った操作はまだありません。"
        ].joined(separator: "\n")
    }
    private var widgetSnapshot: FlowWidgetSnapshot?
    private var widgetDay: Date?
    var widgetEnabled: Bool { FlowWidgetContainer.file != nil }
    let clock = FlowClock()
    let reminders = FlowReminders()
    let appleReminders = FlowAppleRemindersLink()
    private let url: URL
    private let usesSharedDataFile: Bool
    private var sharedBase: Data?
    private var needsMigrationCopy = false
    private static let maxDataBytes = 20 * 1024 * 1024
    private static let maxCarriesPerWrite = 10_000
    private struct SchemaHeader: Decodable { let schemaVersion: Int }
    private enum SharedWriteError: Error { case changed }
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = support.appendingPathComponent("LifeFlow", isDirectory: true)
            .appendingPathComponent("lifeflow.json")
        let sharedURL = FlowWidgetContainer.dataFile
        #if DEBUG && targetEnvironment(simulator)
        let fixtureID = ProcessInfo.processInfo.environment["LIFEFLOW_UI_TEST_STORE"].flatMap(UUID.init(uuidString:))
        if let fixtureID {
            let fixtureDirectory = support.appendingPathComponent("LifeFlowUITests", isDirectory: true)
                .appendingPathComponent(fixtureID.uuidString, isDirectory: true)
            url = fixtureDirectory.appendingPathComponent("lifeflow.json")
            usesSharedDataFile = false
        } else {
            url = sharedURL ?? legacyURL
            usesSharedDataFile = sharedURL != nil
        }
        #else
        url = sharedURL ?? legacyURL
        usesSharedDataFile = sharedURL != nil
        #endif
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Keep the old private file intact and copy it only once into the app group.
            if usesSharedDataFile, !FileManager.default.fileExists(atPath: url.path),
               FileManager.default.fileExists(atPath: legacyURL.path) {
                let oldBytes = try Data(contentsOf: legacyURL)
                try FlowWidgetSharedDataFile.updateData(at: url, sharedGroup: true) { current in
                    current == nil ? oldBytes : nil
                }
            }
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
            #if DEBUG && targetEnvironment(simulator)
            if fixtureID != nil && !FileManager.default.fileExists(atPath: url.path) {
                let today = clock.today()
                let tomorrow = clock.calendar.date(byAdding: .day, value: 1, to: today)!
                let fixture = FlowData(tasks: [
                    FlowTask(id: UUID(uuidString: "61565EF1-4DD7-4962-B996-949D0E15D75F")!, title: "A Normal", day: today),
                    FlowTask(title: "B Daily", day: today, repeatRule: .daily),
                    FlowTask(title: "C Habit", day: today, category: "習慣", habitGoal: 3),
                    FlowTask(id: UUID(uuidString: "EF6A4AF5-6253-4D4D-B67B-9DC9BFE33F50")!, title: "D Future", day: tomorrow)
                ])
                try Self.encode(fixture).write(to: url, options: [.atomic, .completeFileProtection])
            }
            #endif
            if FileManager.default.fileExists(atPath: url.path) {
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.maxDataBytes {
                    throw FlowError.invalidBackup
                }
                let bytes = try FlowWidgetSharedDataFile.readData(from: url)
                data = try Self.decode(bytes)
                if usesSharedDataFile { sharedBase = bytes }
                needsMigrationCopy = try JSONDecoder().decode(SchemaHeader.self, from: bytes).schemaVersion < FlowData.currentSchema
            }
            ready = true
            if !appleReminders.enabled { roll() }
            reminders.update(data.tasks)
        } catch { self.error = "保存データを読み込めません。元ファイルを保護しています。バックアップから復元してください。\n\(error.localizedDescription)" }
    }
    static func encode(_ value: FlowData) throws -> Data {
        try FlowWidgetSharedDataFile.encode(value)
    }
    static func decode(_ bytes: Data) throws -> FlowData {
        try FlowWidgetSharedDataFile.decode(bytes)
    }
    @discardableResult private func commit(_ candidate: FlowData, restoring: Bool = false,
                                           updateAppleReminders: Bool = true) -> Bool {
        guard ready || restoring else { return false }
        do {
            var validated = try candidate.validated()
            let today = clock.today()
            for index in validated.history.indices where validated.history[index].completionUndo != nil {
                if clock.today(validated.history[index].recordedAt) < today {
                    validated.history[index].completionUndo = nil
                }
            }
            let bytes = try Self.encode(validated)
            guard bytes.count <= Self.maxDataBytes else { throw FlowError.invalidBackup }
            if restoring {
                try FlowWidgetSharedDataFile.writeData(bytes, to: url, sharedGroup: usesSharedDataFile) { currentURL in
                    if FileManager.default.fileExists(atPath: currentURL.path) {
                        try backupFile(at: currentURL, restoring: true)
                    }
                }
            } else if usesSharedDataFile {
                try FlowWidgetSharedDataFile.updateData(at: url, sharedGroup: true) { current in
                    guard current == sharedBase else { throw SharedWriteError.changed }
                    if let current, needsMigrationCopy {
                        try current.write(to: safetyBackupURL(restoring: false), options: [.atomic, .completeFileProtection])
                    }
                    return bytes
                }
            } else {
                if needsMigrationCopy && FileManager.default.fileExists(atPath: url.path) {
                    try backupFile(at: url, restoring: false)
                }
                try FlowWidgetSharedDataFile.writeData(bytes, to: url, sharedGroup: false)
            }
            if usesSharedDataFile { sharedBase = bytes }
            needsMigrationCopy = false
            data = validated; ready = true; error = nil
            reminders.update(data.tasks)
            refreshWidget()
            if updateAppleReminders { appleReminders.scheduleSync(store: self) }
            return true
        } catch SharedWriteError.changed {
            synchronizeWidgetChanges()
            error = "ウィジェットからの変更を読み込みました。もう一度操作してください。"
            return false
        } catch { self.error = "保存できませんでした。変更は反映していません。\n\(error.localizedDescription)"; return false }
    }

    private func safetyBackupURL(restoring: Bool) -> URL {
        let prefix = restoring ? "before-restore" : "before-migration"
        return url.deletingLastPathComponent().appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    private func backupFile(at source: URL, restoring: Bool) throws {
        let safety = safetyBackupURL(restoring: restoring)
        try FileManager.default.copyItem(at: source, to: safety)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: safety.path)
    }

    func synchronizeWidgetChanges() {
        guard ready, usesSharedDataFile else { return }
        do {
            guard let bytes = try FlowWidgetSharedDataFile.readIfPresent(from: url), bytes != sharedBase else { return }
            data = try Self.decode(bytes)
            sharedBase = bytes
            needsMigrationCopy = try JSONDecoder().decode(SchemaHeader.self, from: bytes).schemaVersion < FlowData.currentSchema
            reminders.update(data.tasks)
        } catch {
            self.error = "ウィジェットと共有する保存データを読み込めませんでした。"
        }
    }
    func roll() {
        guard ready else { return }
        var next = data
        guard next.rollover(now: Date(), clock: clock, maxCarries: Self.maxCarriesPerWrite) else {
            error = "古い予定が多いため自動繰り越しを停止しました。元データは保存されています。"
            return
        }
        if next.tasks != data.tasks { commit(next) }
        else if widgetDay != clock.today() { refreshWidget() }
    }

    func refreshToday() {
        if appleReminders.enabled { appleReminders.scheduleSync(store: self) }
        else { roll() }
    }

    func importAppleReminderCompletions(_ incoming: [(FlowAppleReminderReference, Date?)]) -> Int? {
        guard ready else { return nil }
        synchronizeWidgetChanges()
        let now = Date()
        var next = data
        var imported = 0
        for (reference, completion) in incoming {
            if reference.complete(in: &next, at: completion, now: now, clock: clock) { imported += 1 }
        }
        return imported == 0 || commit(next, updateAppleReminders: false) ? imported : nil
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
        guard ready else { return }
        var next = data
        switch next.resolveDisplayedTask(task, outcome: outcome, now: Date(), clock: clock,
                                         maxCarries: Self.maxCarriesPerWrite) {
        case .resolved: commit(next)
        case .stale: break
        case .blocked(let reason): error = reason.message
        case .rolloverLimit: error = "古い予定が多いため処理を停止しました。元データは保存されています。"
        }
    }

    func undoCompletion(_ eventID: UUID) {
        guard ready, data.history.contains(where: { $0.id == eventID }) else { return }
        var next = data
        if next.undoCompletion(eventID, now: Date(), clock: clock) {
            commit(next)
        } else {
            error = "この記録は取り消せません。"
        }
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

    func setWidgetShowsTitles(_ value: Bool) {
        widgetShowsTitles = value
        UserDefaults.standard.set(value, forKey: "widgetShowsTitles")
        refreshWidget()
    }

    func setWidgetOpensForCompletion(_ value: Bool) {
        widgetOpensForCompletion = value
        UserDefaults.standard.set(value, forKey: "widgetOpensForCompletion")
        refreshWidget()
    }

    func refreshWidget(force: Bool = false) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["LIFEFLOW_UI_TEST_STORE"] != nil { return }
        #endif
        guard ready else { return }
        guard let file = FlowWidgetContainer.file else {
            if force { error = "ウィジェットとデータを共有できません。AltStoreでウィジェット付きIPAを使い、拡張機能を残してインストールしてください。" }
            return
        }
        let now = Date()
        let snapshot = FlowWidgetSnapshot(data: data, now: now, clock: clock, showTitles: widgetShowsTitles,
                                          opensForCompletion: widgetOpensForCompletion)
        if !force, snapshot == widgetSnapshot, FileManager.default.fileExists(atPath: file.path) { return }
        do {
            try FlowWidgetSharedDataFile.writeData(JSONEncoder().encode(snapshot), to: file, sharedGroup: true)
            widgetSnapshot = snapshot
            widgetDay = clock.today(now)
        } catch {
            // If a refresh fails, do not leave previously shared task names behind.
            try? FileManager.default.removeItem(at: file)
            widgetSnapshot = nil
            if force { self.error = "ウィジェットの表示を更新できませんでした。" }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind)
    }

    @discardableResult
    func completeWidgetTask(_ id: UUID, occurrenceDay: Date, displayedDay: Date? = nil) -> Bool {
        guard ready else {
            recordWidgetAction("丸ボタンを受け取りましたが、データを読み込めませんでした")
            return false
        }
        synchronizeWidgetChanges()
        let now = Date()
        guard let completed = FlowWidgetTaskAction.complete(id, occurrenceDay: occurrenceDay,
                                                            displayedDay: displayedDay,
                                                            data: data, now: now, clock: clock) else {
            error = "ウィジェットの予定が更新されています。表示を更新してから、もう一度お試しください。"
            recordWidgetAction("丸ボタンを受け取りましたが、現在の予定と一致しませんでした")
            WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetContainer.kind)
            return false
        }
        let saved = commit(completed)
        recordWidgetAction(saved ? "丸ボタンで達成を保存しました" : "丸ボタンを受け取りましたが、保存できませんでした")
        return saved
    }

    func recordWidgetAction(_ message: String) {
        lastAppWidgetAction = FlowWidgetActionReport(date: Date(), message: message)
    }

    func planToday(_ id: UUID, enabled: Bool) {
        var next = data
        if next.setPlannedToday(id, enabled: enabled, now: Date(), clock: clock) { commit(next) }
    }

    func changeDeadline(_ id: UUID, to date: Date) {
        var next = data
        guard next.changeDeadline(id, to: date, clock: clock) else { return }
        guard next.rollover(now: Date(), clock: clock, maxCarries: Self.maxCarriesPerWrite) else {
            error = "期限を変更できませんでした。"
            return
        }
        commit(next)
    }

    func reorderToday(_ visible: [UUID], to reordered: [UUID]) {
        var next = data
        if next.reorderToday(visible, to: reordered, now: Date(), clock: clock) { commit(next) }
    }

    func editPastHabit(_ id: UUID, day: Date, outcome: FlowHabitOutcome?) {
        var next = data
        if next.editPastHabit(id, day: day, outcome: outcome, now: Date(), clock: clock) { commit(next) }
    }

    func restHabit(_ id: UUID) {
        var next = data
        if next.markHabit(id, outcome: .rest, now: Date(), clock: clock) { commit(next) }
    }
}
