import SwiftUI

struct FlowTaskSearch: View {
    @EnvironmentObject private var store: FlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editing: FlowTask?

    var body: some View {
        NavigationStack {
            List {
                let results = FlowTaskList(tasks: store.data.tasks, query: query, now: Date(), clock: store.clock).all
                if results.isEmpty { Text("一致するToDoはありません").foregroundStyle(.secondary) }
                ForEach(results) { task in
                    Button { editing = task } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.headline)
                            Text(store.clock.label(task.deadline)).font(.caption)
                            if !task.note.isEmpty { Text(task.note).font(.caption).lineLimit(2) }
                        }.foregroundStyle(task.originDay == nil ? FlowTheme.ink : Color.red)
                    }
                }
            }
            .flowScreen()
            .searchable(text: $query, prompt: "タイトル・メモ・サブタスク")
            .navigationTitle("ToDoを検索")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .sheet(item: $editing) { TaskEditor(task: $0) }
        }
    }
}
