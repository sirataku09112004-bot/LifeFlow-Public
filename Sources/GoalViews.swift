import SwiftUI

struct FlowGoalsView: View {
    @EnvironmentObject private var store: FlowStore
    @State private var newGoal: FlowGoal?

    var body: some View {
        NavigationStack {
            List {
                if store.data.annualGoals.isEmpty { Text("＋から年間目標を追加できます。").foregroundStyle(.secondary) }
                ForEach(store.data.annualGoals.sorted { $0.deadline < $1.deadline }) { goal in
                    NavigationLink {
                        FlowGoalDetail(goalID: goal.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(goal.title).font(.headline)
                            Label(store.clock.label(goal.deadline), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(!goal.isDone && goal.deadline < store.clock.today() ? Color.red : FlowTheme.ink)
                            ProgressView(value: goal.progress).tint(FlowTheme.accent)
                            Text(goal.isDone ? "達成" : "\(goal.completedSteps)/\(goal.steps.count)完了")
                                .font(.caption)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .flowScreen()
            .navigationTitle("年間目標")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let today = store.clock.today()
                        let yearEnd = store.clock.calendar.dateInterval(of: .year, for: today)
                            .map { store.clock.day($0.end.addingTimeInterval(-1)) } ?? today
                        newGoal = FlowGoal(title: "", deadline: yearEnd)
                    } label: {
                        Image(systemName: "plus.circle.fill").accessibilityLabel("年間目標を追加")
                    }.disabled(!store.ready)
                }
            }
            .sheet(item: $newGoal) { FlowGoalEditor(goal: $0) }
        }
    }
}

struct FlowGoalDetail: View {
    @EnvironmentObject private var store: FlowStore
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    @State private var editing: FlowGoal?
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        List {
            if let goal = store.data.annualGoals.first(where: { $0.id == goalID }) {
                Section {
                    Text(goal.title).font(.title2.bold())
                    Label(store.clock.label(goal.deadline), systemImage: "calendar")
                    ProgressView(value: goal.progress).tint(FlowTheme.accent)
                    Text("\(goal.completedSteps)/\(goal.steps.count)完了・\(Int((goal.progress * 100).rounded()))%")
                    Button(goal.isDone ? "未達成に戻す" : "目標を達成にする") {
                        var updated = goal
                        updated.isDone.toggle()
                        if !store.saveGoal(updated) { message = store.error }
                    }
                }
                Section("サブタスク") {
                    if goal.steps.isEmpty { Text("編集からサブタスクを追加できます。").foregroundStyle(.secondary) }
                    ForEach(goal.steps) { step in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                var updated = goal
                                if let index = updated.steps.firstIndex(where: { $0.id == step.id }) {
                                    updated.steps[index].isDone.toggle()
                                    if !store.saveGoal(updated) { message = store.error }
                                }
                            } label: {
                                Label(step.title, systemImage: step.isDone ? "checkmark.circle.fill" : "circle")
                            }
                            if !step.isDone && !goal.isDone {
                                let alreadyAdded = store.data.tasks.contains { $0.goalStepID == step.id }
                                Button(alreadyAdded ? "ToDoに追加済み" : "今日のToDoに追加") {
                                    if !store.addGoalStepToToday(step.id, goalID: goal.id) { message = store.error }
                                }
                                .font(.caption)
                                .disabled(alreadyAdded)
                            }
                        }.buttonStyle(.borderless)
                    }
                }
                Button("目標を削除", role: .destructive) { confirmingDelete = true }
                if let message { Text(message).foregroundStyle(.red) }
            }
        }
        .flowScreen()
        .navigationTitle("目標の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("編集") { editing = store.data.annualGoals.first { $0.id == goalID } }
            }
        }
        .sheet(item: $editing) { FlowGoalEditor(goal: $0) }
        .confirmationDialog("年間目標を削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if store.deleteGoal(goalID) { dismiss() } else { message = store.error }
            }
        }
    }
}

struct FlowGoalEditor: View {
    @EnvironmentObject private var store: FlowStore
    @Environment(\.dismiss) private var dismiss
    @State var goal: FlowGoal
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("年間目標", text: $goal.title, axis: .vertical)
                DatePicker("目標期限", selection: $goal.deadline, displayedComponents: .date)
                FlowChecklistEditor(items: $goal.steps, goalMode: true)
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .flowScreen()
            .navigationTitle("年間目標を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var candidate = goal
                        candidate.title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        candidate.deadline = store.clock.day(goal.deadline)
                        candidate.steps = goal.steps.map {
                            var step = $0
                            step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            return step
                        }
                        if store.saveGoal(candidate) { dismiss() } else { saveError = store.error }
                    }.disabled(goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
