import EventKit
import SwiftUI

@MainActor final class FlowAppleRemindersLink: ObservableObject {
    static let listTitle = "LifeFlow・今日のToDo"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "appleReminders.enabled")
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    private let events = EKEventStore()
    private let defaults = UserDefaults.standard
    private var running = false
    private var requested = false
    private enum LinkError: Error { case missingList, missingAccount, readFailed, saveFailed }

    func setEnabled(_ value: Bool, store: FlowStore) async {
        if !value {
            enabled = false
            defaults.set(false, forKey: "appleReminders.enabled")
            status = "連携を停止しました。リマインダーに作成済みの項目は残ります。"
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let granted: Bool
            if #available(iOS 17.0, *) { granted = try await events.requestFullAccessToReminders() }
            else { granted = try await events.requestAccess(to: .reminder) }
            guard granted else {
                status = "iPhoneの設定でリマインダーへのアクセスを許可してください。"
                return
            }
            _ = try list(create: true)
            enabled = true
            defaults.set(true, forKey: "appleReminders.enabled")
            scheduleSync(store: store)
        } catch { status = "専用リストを用意できませんでした。リマインダーのアカウント設定を確認してください。" }
    }

    func scheduleSync(store: FlowStore) {
        guard enabled, store.ready else { return }
        requested = true
        guard !running else { return }
        running = true
        Task { [weak store] in
            defer { running = false }
            while enabled, requested, let store {
                requested = false
                await synchronize(store: store)
            }
        }
    }

    private func list(create: Bool) throws -> EKCalendar {
        if let identifier = defaults.string(forKey: "appleReminders.list") {
            if let existing = events.calendar(withIdentifier: identifier), existing.allowsContentModifications {
                return existing
            }
            if !create { throw LinkError.missingList }
        }
        let local = events.sources.first { $0.sourceType == .local && !$0.calendars(for: .reminder).isEmpty }
        guard let source = local ?? events.defaultCalendarForNewReminders()?.source else { throw LinkError.missingAccount }
        let list = EKCalendar(for: .reminder, eventStore: events)
        list.title = Self.listTitle
        list.source = source
        try events.saveCalendar(list, commit: true)
        defaults.set(list.calendarIdentifier, forKey: "appleReminders.list")
        return list
    }

    private func synchronize(store: FlowStore) async {
        let authorization = EKEventStore.authorizationStatus(for: .reminder)
        let allowed: Bool
        if #available(iOS 17.0, *) { allowed = authorization == .fullAccess }
        else { allowed = authorization == .authorized }
        guard allowed else {
            status = "iPhoneの設定でリマインダーへのアクセスを許可してください。"
            store.roll()
            return
        }
        do {
            let calendar = try list(create: false)
            let predicate = events.predicateForReminders(in: [calendar])
            let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
                events.fetchReminders(matching: predicate) { reminders in
                    if let reminders { continuation.resume(returning: reminders) }
                    else { continuation.resume(throwing: LinkError.readFailed) }
                }
            }
            guard enabled else { return }
            let owner: UUID
            if let value = defaults.string(forKey: "appleReminders.owner").flatMap(UUID.init(uuidString:)) { owner = value }
            else {
                owner = UUID()
                defaults.set(owner.uuidString, forKey: "appleReminders.owner")
            }
            let managed = reminders.compactMap { reminder in
                FlowAppleReminderReference(url: reminder.url, owner: owner).map { ($0, reminder) }
            }
            let completions = managed.filter { $0.1.isCompleted }.sorted {
                ($0.1.completionDate ?? .distantFuture) < ($1.1.completionDate ?? .distantFuture)
            }
            let handled = Set(defaults.stringArray(forKey: "appleReminders.handled") ?? [])
            let incoming = completions.filter { !handled.contains($0.1.calendarItemIdentifier) }
            guard let imported = store.importAppleReminderCompletions(incoming.map { ($0.0, $0.1.completionDate) }) else {
                throw LinkError.saveFailed
            }
            // Keep imported actions consumed if the external write fails and the user later undoes a completion.
            let consumed = completions.map { $0.1.calendarItemIdentifier }
            defaults.set(consumed, forKey: "appleReminders.handled")
            store.roll()
            let now = Date()
            let day = store.clock.today(now)
            let tasks = FlowTaskList(tasks: store.data.tasks, query: "", now: now, clock: store.clock,
                                     todayOrder: store.data.todayOrder ?? []).today.filter {
                store.data.resolutionBlock(for: $0, now: now, clock: store.clock) == nil
            }
            var pending = Dictionary(uniqueKeysWithValues: tasks.map {
                (FlowAppleReminderReference(task: $0, displayedDay: day, clock: store.clock), $0.title)
            })
            do {
                for (reference, reminder) in managed {
                    if !reminder.isCompleted, let title = pending.removeValue(forKey: reference) {
                        if reminder.title != title {
                            reminder.title = title
                            try events.save(reminder, commit: false)
                        }
                    } else { try events.remove(reminder, commit: false) }
                }
                for (reference, title) in pending {
                    let reminder = EKReminder(eventStore: events)
                    reminder.calendar = calendar
                    reminder.title = title
                    reminder.url = reference.url(owner: owner)
                    try events.save(reminder, commit: false)
                }
                try events.commit()
                defaults.removeObject(forKey: "appleReminders.handled")
            } catch {
                events.reset()
                throw error
            }
            let skipped = incoming.count - imported
            status = "\(tasks.count)件を表示しました。" + (imported > 0 ? "達成を\(imported)件取り込みました。" : "") +
                (skipped > 0 ? "予定が変わった\(skipped)件は取り込みませんでした。" : "")
        } catch LinkError.missingList {
            status = "専用リストが見つかりません。連携を一度オフにしてからオンにすると作り直せます。"
            store.roll()
        } catch {
            status = "同期できませんでした。次にLifeFlowを開くと再試行します。"
        }
    }
}

struct FlowAppleRemindersSettings: View {
    @ObservedObject var link: FlowAppleRemindersLink
    let store: FlowStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("今日のToDoをリマインダーに表示", isOn: Binding(
                        get: { link.enabled }, set: { value in Task { await link.setEnabled(value, store: store) } }
                    )).disabled(link.busy || !store.ready)
                    if link.enabled { Button("今すぐ同期") { link.scheduleSync(store: store) } }
                    if !link.status.isEmpty { Text(link.status).font(.footnote) }
                } footer: {
                    Text("「\(FlowAppleRemindersLink.listTitle)」にタスク名を表示します。リマインダーの設定によってはiCloudにも同期されます。連携にはリマインダーへのフルアクセスが必要です。")
                }
                Section("ホーム画面で使う") {
                    Text("標準の「リマインダー」ウィジェットを追加し、長押しして専用リストを選びます。丸を押すとリマインダーで完了し、次にLifeFlowを開いたときに達成を取り込みます。新しい日の一覧もLifeFlowを開くと更新されます。")
                }
            }
            .navigationTitle("標準リマインダー連携")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}
