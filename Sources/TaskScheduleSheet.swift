import SwiftUI

struct TaskScheduleSheet: View {
    @EnvironmentObject private var store: FlowStore
    @Environment(\.dismiss) private var dismiss
    let task: FlowTask
    @State private var custom = false
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                let today = store.clock.today()
                let isPlanned = task.isPlannedToday(today, clock: store.clock)
                Section("取り組む予定") {
                    Button(isPlanned ? "「今日やる」を解除" : "今日やる予定に追加") {
                        store.planToday(task.id, enabled: !isPlanned)
                        dismiss()
                    }
                }
                Section("締切日を変更") {
                    Text(store.clock.label(task.deadline)).foregroundStyle(.secondary)
                    Button("今日") { changeDeadline(plus: 0) }
                    Button("明日") { changeDeadline(plus: 1) }
                    Button("来週（7日後）") { changeDeadline(plus: 7) }
                    Button("日付指定") { date = task.deadline; custom = true }
                    if custom {
                        DatePicker("締切日", selection: $date, displayedComponents: .date)
                        Button("指定した締切日に変更") {
                            store.changeDeadline(task.id, to: date)
                            dismiss()
                        }
                    }
                }
            }
            .flowScreen()
            .navigationTitle("予定と締切")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func changeDeadline(plus days: Int) {
        if let target = store.clock.calendar.date(byAdding: .day, value: days, to: store.clock.today()) {
            store.changeDeadline(task.id, to: target)
            dismiss()
        }
    }
}
