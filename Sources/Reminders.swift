import SwiftUI
import UserNotifications

@MainActor final class FlowReminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var enabled: Bool
    @Published private(set) var settings: FlowReminderSettings
    @Published private(set) var upcoming: [FlowReminder] = []
    @Published private(set) var testStatus = ""
    @Published private(set) var status = "通知はオフです"
    @Published private(set) var scheduled = 0
    @Published private(set) var requesting = false
    @Published private(set) var checkInEnabled = UserDefaults.standard.bool(forKey: "reminders.checkInEnabled")
    @Published private(set) var checkInTime: Int
    @Published private(set) var checkInStatus = ""
    private var lastOpened = UserDefaults.standard.object(forKey: "reminders.lastOpened") as? Date
    private let center = UNUserNotificationCenter.current()
    private var desired: [FlowTask]?
    private var refreshing = false
    override init() {
        enabled = UserDefaults.standard.bool(forKey: "reminders.enabled")
        settings = FlowReminderSettings.load(UserDefaults.standard.data(forKey: "reminders.settings.v1"),
                                             legacyHour: UserDefaults.standard.object(forKey: "reminders.hour") as? Int)
        let storedCheckInTime = UserDefaults.standard.object(forKey: "reminders.checkInTime") as? Int ?? 21 * 60
        checkInTime = (240...1439).contains(storedCheckInTime) ? storedCheckInTime : 21 * 60
        super.init()
        center.delegate = self
    }
    func setEnabled(_ value: Bool, tasks: [FlowTask]) async {
        guard !requesting else { return }
        if value {
            requesting = true
            defer { requesting = false }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                enabled = granted
                if !granted { status = "通知が許可されていません。iPhoneの設定から変更できます。" }
            } catch { status = "通知の許可を確認できません：\(error.localizedDescription)"; enabled = false }
        } else { enabled = false }
        UserDefaults.standard.set(enabled, forKey: "reminders.enabled")
        update(tasks)
    }
    func markOpened(now: Date, clock: FlowClock, tasks: [FlowTask]) {
        let day = clock.today(now)
        guard lastOpened.map({ clock.today($0) }) != day else { return }
        lastOpened = now
        UserDefaults.standard.set(now, forKey: "reminders.lastOpened")
        center.removePendingNotificationRequests(withIdentifiers: [FlowCheckIn.identifier(for: day)])
        update(tasks)
    }

    func setCheckInEnabled(_ value: Bool, tasks: [FlowTask]) async {
        guard !requesting else { return }
        if value {
            requesting = true
            defer { requesting = false }
            do {
                checkInEnabled = try await center.requestAuthorization(options: [.alert, .sound])
                if !checkInEnabled { checkInStatus = "iPhoneの設定で通知を許可してください。" }
            } catch {
                checkInStatus = "通知の許可を確認できませんでした。"
            }
        } else {
            checkInEnabled = false
            checkInStatus = ""
        }
        UserDefaults.standard.set(checkInEnabled, forKey: "reminders.checkInEnabled")
        update(tasks)
    }

    func setCheckInTime(_ value: Int, tasks: [FlowTask]) {
        guard (240...1439).contains(value) else { return }
        checkInTime = value
        UserDefaults.standard.set(value, forKey: "reminders.checkInTime")
        update(tasks)
    }

    func configure(_ value: FlowReminderSettings, tasks: [FlowTask]) {
        settings = value.normalized()
        if let bytes = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(bytes, forKey: "reminders.settings.v1") }
        testStatus = ""
        center.removePendingNotificationRequests(withIdentifiers: ["lifeflow.test"])
        update(tasks)
    }
    func sendTest() async {
        guard enabled, !requesting else { return }
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else {
            testStatus = "iPhoneの設定で通知を許可してください。"; return
        }
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "LifeFlow・テスト通知"
        content.body = settings.showTitle ? "通知の表示と音を確認してください。" : "ToDoを確認してください。"
        content.sound = settings.sound ? .default : nil
        do {
            try await center.add(UNNotificationRequest(identifier: "lifeflow.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            testStatus = "5秒後にテスト通知を送ります。曜日や対象の条件には関係なく通知します。"
        } catch { testStatus = "テスト通知を予約できません：\(error.localizedDescription)" }
    }
    func update(_ tasks: [FlowTask]) {
        // One worker drains the latest snapshot, so old requests cannot finish after newer rebuilds.
        desired = tasks
        guard !refreshing else { return }
        refreshing = true
        Task {
            while let snapshot = desired {
                desired = nil
                await rebuild(snapshot)
            }
            refreshing = false
        }
    }
    private func rebuild(_ tasks: [FlowTask]) async {
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.identifier.hasPrefix("lifeflow.") && ($0.identifier != "lifeflow.test" || !enabled)
        }.map(\.identifier))
        scheduled = 0; upcoming = []
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            status = "iPhoneの設定で通知を許可できます。"
            if checkInEnabled { checkInStatus = status }
            return
        }
        let clock = FlowClock()
        let configuration = self.settings
        let plan = enabled ? FlowReminderPlan.make(tasks: tasks, settings: configuration, now: Date(), clock: clock) : []
        var failures = 0
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.heading
            content.body = configuration.showTitle ? item.title : "ToDoを確認してください。"
            content.sound = configuration.sound ? .default : nil
            let calendarTrigger = trigger(for: item.fireDate, clock: clock)
            do {
                try await center.add(UNNotificationRequest(identifier: item.requestID, content: content, trigger: calendarTrigger))
                scheduled += 1; upcoming.append(item)
            } catch { failures += 1 }
        }
        if !enabled { status = "ToDoの予定日通知はオフです" }
        else if failures == 0 { status = "\(scheduled)件を予約しました（近い順に最大60件）" }
        else { status = "\(scheduled)件を予約、\(failures)件の予約に失敗しました。" }

        guard checkInEnabled else { return }
        let checkIns = FlowCheckIn.plan(now: Date(), lastOpened: lastOpened, minuteOfDay: checkInTime,
                                      clock: clock, available: 63 - scheduled)
        var added = 0
        for item in checkIns {
            guard checkInEnabled, desired == nil else { return }
            let content = UNMutableNotificationContent()
            content.title = "LifeFlow"
            content.body = "今日のToDoは確認しましたか？"
            content.sound = configuration.sound ? .default : nil
            let request = UNNotificationRequest(identifier: item.identifier, content: content,
                                                trigger: trigger(for: item.fireDate, clock: clock))
            do {
                try await center.add(request)
                if !checkInEnabled || lastOpened.map({ clock.today($0) }) == item.day {
                    center.removePendingNotificationRequests(withIdentifiers: [item.identifier])
                } else { added += 1 }
            } catch { continue }
        }
        checkInStatus = "\(added)日分を予約しました。"
        if added < checkIns.count { checkInStatus += " 一部の予約に失敗しました。" }
    }

    private func trigger(for date: Date, clock: FlowClock) -> UNCalendarNotificationTrigger {
        var parts = clock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.calendar = clock.calendar
        parts.timeZone = clock.calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier.hasPrefix("lifeflow.check-in.") {
            completionHandler([])
            return
        }
        completionHandler(notification.request.content.sound == nil ? [.banner] : [.banner, .sound])
    }
}

