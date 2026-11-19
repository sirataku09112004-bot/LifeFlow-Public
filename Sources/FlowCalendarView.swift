import SwiftUI

struct FlowCalendarView: View {
    @EnvironmentObject private var store: FlowStore
    @State private var selection: Date?
    @State private var now = Date()
    @State private var editing: FlowTask?
    @State private var adding: FlowTask?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private var today: Date { store.clock.today(now) }
    private var selectedDay: Date { selection ?? today }

    var body: some View {
        NavigationStack {
            let month = FlowCalendarMonth(containing: selectedDay, tasks: store.data.tasks, clock: store.clock)
            List {
                Section {
                    monthGrid(month)
                        .padding(.vertical, 4)
                }
                Section(store.clock.label(selectedDay)) {
                    let items = month.itemsByDay[selectedDay] ?? []
                    if items.isEmpty {
                        Text("この日の予定はありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        Button { editing = item.task } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.task.title)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    if item.isDeadline {
                                        Label(item.task.habitGoal == nil ? "締切" : "習慣の予定", systemImage: "calendar")
                                    }
                                    if item.isPlanned { Label("今日やる", systemImage: "checklist") }
                                }
                                .font(.caption)
                                .foregroundStyle(FlowTheme.action)
                            }
                            .foregroundStyle(FlowTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("calendar-task:" + item.task.title)
                    }
                }
            }
            .flowScreen()
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("今日") { selection = nil }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        adding = FlowTask(title: "", day: selectedDay)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityLabel("選択した日にToDoを追加")
                    }
                    .disabled(!store.ready)
                }
            }
            .sheet(item: $editing) { task in TaskEditor(task: task).environmentObject(store) }
            .sheet(item: $adding) { task in TaskEditor(task: task).environmentObject(store) }
            .onReceive(timer) { now = $0 }
            .onAppear { now = Date() }
        }
    }

    private func monthGrid(_ month: FlowCalendarMonth) -> some View {
        VStack(spacing: 8) {
            HStack {
                monthButton("前の月", symbol: "chevron.left", offset: -1, from: month.start)
                Spacer(minLength: 4)
                let parts = store.clock.calendar.dateComponents([.year, .month], from: month.start)
                Text("\(parts.year ?? 0)年\(parts.month ?? 0)月")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                monthButton("次の月", symbol: "chevron.right", offset: 1, from: month.start)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<month.leadingDays, id: \.self) { _ in Color.clear }
                ForEach(month.days, id: \.self) { day in
                    dayButton(day, count: month.itemsByDay[day]?.count ?? 0)
                }
            }
        }
    }

    private func monthButton(_ label: String, symbol: String, offset: Int, from start: Date) -> some View {
        Button {
            selection = store.clock.calendar.date(byAdding: .month, value: offset, to: start)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(FlowTheme.action)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Date, count: Int) -> some View {
        let isSelected = selectedDay == day
        return Button { selection = day } label: {
            VStack(spacing: 3) {
                Text(store.clock.calendar.component(.day, from: day), format: .number)
                    .font(.subheadline.monospacedDigit().weight(day == today ? .bold : .regular))
                Circle()
                    .fill(count == 0 ? Color.clear : (isSelected ? .white : FlowTheme.action))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? FlowTheme.action : (day == today ? FlowTheme.pale : .clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isSelected ? .white : FlowTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.clock.label(day))
        .accessibilityValue("\(count)件")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
