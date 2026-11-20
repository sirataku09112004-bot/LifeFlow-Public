import SwiftUI

struct FlowHabitList: View {
    @EnvironmentObject private var store: FlowStore
    @State private var adding: FlowTask?
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            let habits = store.data.tasks.filter { $0.habitGoal != nil }
            if habits.isEmpty {
                Text("＋から習慣を追加できます。")
                    .foregroundStyle(.secondary)
            }
            ForEach(habits) { task in
                if let target = task.habitGoal {
                    habitCard(task, target: target)
                        .listRowBackground(FlowTheme.card)
                }
            }
        }
        .flowScreen()
        .navigationTitle("習慣")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    adding = FlowTask(title: "", day: store.clock.today(), category: "習慣", habitGoal: 3)
                } label: {
                    Image(systemName: "plus.circle.fill").accessibilityLabel("習慣を追加")
                }
                .disabled(!store.ready)
            }
        }
        .sheet(item: $adding) { TaskEditor(task: $0).environmentObject(store) }
        .onAppear { now = Date() }
        .onReceive(timer) { now = $0 }
    }

    private func habitCard(_ task: FlowTask, target: Int) -> some View {
        let calendar = FlowHabitCalendar(taskID: task.id, days: store.data.habitDays, now: now, clock: store.clock)
        let week = calendar.interval(month: false, offset: 0)
        let count = week.map { calendar.counts(in: $0).completed } ?? 0
        let dayRecord = calendar.records[calendar.today]
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                FlowHabitDetail(taskID: task.id)
            } label: {
                Text(task.title).font(.headline)
            }
            HStack {
                Text("今週 \(count)/\(target)回")
                Spacer()
                Text("連続 \(calendar.streak)日")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                let days = (-13...0).compactMap { store.clock.calendar.date(byAdding: .day, value: $0, to: calendar.today) }
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(habitDotColor(calendar.records[day]))
                        .overlay(Circle().strokeBorder(day == calendar.today ? FlowTheme.action : .clear, lineWidth: 1.5))
                        .frame(height: 13)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(store.clock.label(day) + "・" + (calendar.records[day]?.label ?? "未記録"))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("直近14日")
            HStack {
                if dayRecord == nil {
                    Button {
                        store.resolve(task, .completed)
                    } label: {
                        Label("今日の達成を記録", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("habit-complete:" + task.title)
                    Spacer()
                    Menu {
                        Button("失敗を記録") { store.resolve(task, .failed) }
                        Button("休養を記録") { store.restHabit(task.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("今日の習慣の操作")
                    }
                } else if let dayRecord {
                    Text("今日：\(dayRecord.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FlowTheme.action)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("habit-today:" + task.title)
                    Spacer()
                    if let event = store.data.completedToday(now: now, clock: store.clock).first(where: { $0.taskID == task.id }),
                       store.data.canUndoCompletion(event.id, now: now, clock: store.clock) {
                        Button("取り消す") { store.undoCompletion(event.id) }
                            .frame(minHeight: 44)
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(!store.ready || task.day > calendar.today && dayRecord == nil)
        }
        .padding(.vertical, 6)
    }
}

private func habitDotColor(_ record: FlowHabitOutcome?) -> Color {
    switch record {
    case .completed: return FlowTheme.accent
    case .failed: return .red
    case .rest: return .yellow
    case nil: return FlowTheme.pale
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
                        Circle().fill(habitDotColor(calendar.records[day])).overlay(Circle().strokeBorder(FlowTheme.ink.opacity(0.25)))
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

}
