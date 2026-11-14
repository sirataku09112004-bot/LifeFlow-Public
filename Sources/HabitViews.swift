import SwiftUI

struct FlowHabitList: View {
    @EnvironmentObject private var store: FlowStore

    var body: some View {
        List {
            let habits = store.data.tasks.filter { $0.habitGoal != nil }
            if habits.isEmpty { Text("ToDoの追加時にカテゴリで「習慣」を選択できます。") }
            ForEach(habits) { task in
                NavigationLink {
                    FlowHabitDetail(taskID: task.id)
                } label: {
                    Label(task.title, systemImage: "circle.grid.2x2")
                }
            }
        }
        .flowScreen()
        .navigationTitle("習慣の記録")
    }
}

struct FlowHabitDetail: View {
    @EnvironmentObject private var store: FlowStore
    let taskID: UUID
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var monthly = true
    @State private var offset = 0
    @State private var selectedDay: Date?
    @State private var showingEdit = false

    private var calendar: FlowHabitCalendar {
        FlowHabitCalendar(taskID: taskID, days: store.data.habitDays, now: now, clock: store.clock)
    }

    var body: some View {
        List {
            if let task = store.data.tasks.first(where: { $0.id == taskID }), let target = task.habitGoal {
                Section {
                    Text(task.title).font(.title2.bold())
                    if let week = calendar.interval(month: false, offset: 0) {
                        let completed = calendar.counts(in: week).completed
                        ProgressView(value: Double(min(completed, target)), total: Double(target)).tint(FlowTheme.accent)
                        Text("今週 \(completed)/\(target)回達成")
                    }
                    Text("連続達成 \(calendar.streak)日")
                    if task.day <= calendar.today && calendar.records[calendar.today] == nil {
                        Button("今日を休養日にする") { store.restHabit(task.id) }
                    }
                }
                calendarSection
            }
        }
        .flowScreen()
        .onReceive(timer) { now = $0 }
        .confirmationDialog("過去の習慣記録を変更", isPresented: $showingEdit, titleVisibility: .visible, presenting: selectedDay) { day in
            Button("達成") { store.editPastHabit(taskID, day: day, outcome: .completed) }
            Button("失敗") { store.editPastHabit(taskID, day: day, outcome: .failed) }
            Button("休養") { store.editPastHabit(taskID, day: day, outcome: .rest) }
            Button("未記録") { store.editPastHabit(taskID, day: day, outcome: nil) }
            Button("キャンセル", role: .cancel) {}
        } message: { day in
            Text(store.clock.label(day))
        }
        .navigationTitle("習慣の詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarSection: some View {
        Section("日別記録") {
            Picker("期間", selection: $monthly) {
                Text("週").tag(false)
                Text("月").tag(true)
            }.pickerStyle(.segmented)
                .onChange(of: monthly) { _ in offset = 0; selectedDay = nil }
            if let interval = calendar.interval(month: monthly, offset: offset) {
                HStack {
                    Button { offset -= 1; selectedDay = nil } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("前の期間")
                    }
                    Spacer()
                    Text(monthly ? interval.start.formatted(.dateTime.year().month()) : store.clock.label(interval.start))
                        .font(.subheadline).multilineTextAlignment(.center)
                    Spacer()
                    Button { offset += 1; selectedDay = nil } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("次の期間")
                    }.disabled(offset >= 0)
                }.buttonStyle(.borderless)
                grid(interval)
                let counts = calendar.counts(in: interval)
                let total = counts.completed + counts.failed
                Text(total == 0 ? "達成率 —" : "達成率 \(Int((100.0 * Double(counts.completed) / Double(total)).rounded()))%")
                Text("水色＝達成　赤＝失敗　黄色＝休養　白＝未記録")
                    .font(.caption).foregroundStyle(.secondary)
                if let selectedDay {
                    Text(store.clock.label(selectedDay) + "・" + status(selectedDay)).font(.footnote)
                        .accessibilityIdentifier("habit-selected-record")
                }
            }
        }
    }

    private func grid(_ interval: DateInterval) -> some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)
        let weekday = store.clock.calendar.component(.weekday, from: interval.start)
        let leading = monthly ? (weekday + 5) % 7 : 0
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array("月火水木金土日"), id: \.self) { Text(String($0)).font(.caption2) }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 26) }
            ForEach(calendar.days(in: interval), id: \.self) { day in
                Button {
                    selectedDay = day
                    if day < store.clock.today() { showingEdit = true }
                } label: {
                    VStack(spacing: 4) {
                        Text(String(store.clock.calendar.component(.day, from: day)))
                            .font(.caption2).minimumScaleFactor(0.65).lineLimit(1)
                        Circle().fill(dotColor(day)).overlay(Circle().strokeBorder(FlowTheme.ink.opacity(0.25)))
                            .frame(width: 10, height: 10)
                    }.frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(store.clock.label(day) + "・" + status(day))
                    .accessibilityIdentifier("habit-day-" + String(Int(day.timeIntervalSince1970)))
            }
        }
    }

    private func status(_ day: Date) -> String {
        calendar.records[day]?.label ?? (day > calendar.today ? "予定" : "未記録")
    }

    private func dotColor(_ day: Date) -> Color {
        switch calendar.records[day] {
        case .completed: return FlowTheme.accent
        case .failed: return .red
        case .rest: return .yellow
        case nil: return .white
        }
    }
}
