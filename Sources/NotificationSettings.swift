import SwiftUI

struct FlowNotificationSettings: View {
    @EnvironmentObject var store: FlowStore
    @ObservedObject var reminders: FlowReminders
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    private func value<T>(_ key: WritableKeyPath<FlowReminderSettings, T>) -> Binding<T> {
        Binding(get: { reminders.settings[keyPath: key] }, set: { newValue in
            var settings = reminders.settings; settings[keyPath: key] = newValue
            reminders.configure(settings, tasks: store.data.tasks)
        })
    }
    private func time(previous: Bool) -> Binding<Date> {
        Binding(get: {
            let s = reminders.settings
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1,
                hour: previous ? s.previousHour : s.hour, minute: previous ? s.previousMinute : s.minute))!
        }, set: { date in
            var s = reminders.settings
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if previous { s.previousHour = parts.hour!; s.previousMinute = parts.minute! }
            else { s.hour = parts.hour!; s.minute = parts.minute! }
            reminders.configure(s, tasks: store.data.tasks)
        })
    }
    private func weekday(_ day: Int) -> Binding<Bool> {
        Binding(get: { reminders.settings.weekdays.contains(day) }, set: { selected in
            var s = reminders.settings
            s.weekdays.removeAll { $0 == day }; if selected { s.weekdays.append(day) }
            reminders.configure(s, tasks: store.data.tasks)
        })
    }
    private var checkInSection: some View {
        Section {
            Toggle("アプリを開いていない日に通知", isOn: Binding(get: { reminders.checkInEnabled }, set: { value in
                Task { await reminders.setCheckInEnabled(value, tasks: store.data.tasks) }
            })).disabled(reminders.requesting || !store.ready)
            if reminders.checkInEnabled {
                Picker("時", selection: Binding(get: { reminders.checkInTime / 60 }, set: {
                    reminders.setCheckInTime($0 * 60 + reminders.checkInTime % 60, tasks: store.data.tasks)
                })) {
                    ForEach(4...23, id: \.self) { Text("\($0)時").tag($0) }
                }
                Picker("分", selection: Binding(get: { reminders.checkInTime % 60 }, set: {
                    reminders.setCheckInTime(reminders.checkInTime / 60 * 60 + $0, tasks: store.data.tasks)
                })) {
                    ForEach(0...59, id: \.self) { Text("\($0)分").tag($0) }
                }
            }
            if !reminders.checkInStatus.isEmpty { Text(reminders.checkInStatus).font(.caption) }
        } header: {
            Text("ToDoの確認")
        } footer: {
            Text("午前4時から指定時刻までアプリを開いていない日に通知します。予約できる期間は、ToDoの通知件数に応じて最長13日です。")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("ToDoを通知する", isOn: Binding(get: { reminders.enabled }, set: { value in
                        Task { await reminders.setEnabled(value, tasks: store.data.tasks) }
                    })).disabled(reminders.requesting || !store.ready)
                    Text(reminders.status).font(.caption).foregroundStyle(.secondary)
                    Button("iPhoneの通知設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                checkInSection
                Group {
                    Section("通知のタイミング") {
                        Toggle("予定日当日", isOn: value(\.onDueDay))
                        if reminders.settings.onDueDay { DatePicker("当日の時刻", selection: time(previous: false), displayedComponents: .hourAndMinute) }
                        Toggle("予定日の前日", isOn: value(\.onPreviousDay))
                        if reminders.settings.onPreviousDay { DatePicker("前日の時刻", selection: time(previous: true), displayedComponents: .hourAndMinute) }
                        if !reminders.settings.onDueDay && !reminders.settings.onPreviousDay {
                            Text("当日か前日をオンにすると予約できます。").foregroundStyle(.orange)
                        }
                    }
                    Section {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Toggle(["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"][day - 1], isOn: weekday(day))
                        }
                        if reminders.settings.weekdays.isEmpty { Text("曜日が未選択のため通知は予約されません。").foregroundStyle(.orange) }
                    } header: { Text("通知する曜日") } footer: {
                        Text("実際に通知する日の曜日です。オフの日の通知は省略し、別の日には移しません。")
                    }
                    Section("対象と表示") {
                        Toggle("★お気に入りだけ通知", isOn: value(\.favoritesOnly))
                        Toggle("通知音を鳴らす", isOn: value(\.sound))
                        Toggle("ToDoのタイトルを表示", isOn: value(\.showTitle))
                    }
                    Section("テスト") {
                        Button("5秒後にテスト通知") { Task { await reminders.sendTest() } }
                            .disabled(!reminders.enabled || reminders.requesting)
                        if !reminders.testStatus.isEmpty { Text(reminders.testStatus).font(.caption).foregroundStyle(.secondary) }
                    }
                    Section("次の通知（先頭5件）") {
                        if reminders.upcoming.isEmpty { Text("予約はありません").foregroundStyle(.secondary) }
                        ForEach(Array(reminders.upcoming.prefix(5)), id: \.requestID) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminders.settings.showTitle ? item.title : "ToDoの通知")
                                Text("\(item.fireDate.formatted(date: .abbreviated, time: .shortened))・\(item.previousDay ? "前日" : "当日")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.disabled(!store.ready)
                Section {
                    Text("設定は自動保存します。通知はカレンダー上の予定日を基準にし、午前0〜3時もその日です。ToDo一覧の午前4時区切りとは異なります。過ぎた時刻は省略します。")
                    Text("当日と前日を合わせて近い順に最大60件予約します。長期間アプリを開かない場合、繰り越しや次回の繰り返し分は新たに予約されません。")
                    Text("通知音や表示はiPhoneの通知設定・集中モードなどにも左右されます。この通知設定は端末内に保存し、JSONバックアップには含めません。")
                }.font(.caption).foregroundStyle(.secondary)
            }
            .flowScreen()
            .navigationTitle("通知設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
