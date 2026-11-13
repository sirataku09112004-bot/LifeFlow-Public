import SwiftUI

struct FlowHistory: View {
    @EnvironmentObject private var store: FlowStore
    @State private var query = ""
    @State private var category: FlowCategoryFilter = .all

    private var history: [FlowEvent] {
        store.data.history.filter { event in
            FlowCategories.matches(event.category, filter: category) && FlowSearch.matches(query, title: event.title, note: (event.subtasks ?? []).map(\.title).joined(separator: " "))
        }.sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        List {
            Picker("カテゴリ", selection: $category) {
                Text("すべて").tag(FlowCategoryFilter.all)
                Text("未分類").tag(FlowCategoryFilter.uncategorized)
                ForEach(FlowCategories.names(store.data.history.map(\.category)), id: \.self) {
                    Text($0).tag(FlowCategoryFilter.named($0))
                }
            }
            if history.isEmpty { Text("表示できる履歴はありません").foregroundStyle(.secondary) }
            ForEach(history) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Label(event.title, systemImage: icon(event.outcome)).font(.headline)
                    Text(label(event.outcome) + (event.outcome == .completed ? "・期限 " : "・対象 ")
                         + store.clock.label(event.outcome == .completed ? event.deadline : event.day)).font(.caption)
                    if let category = event.category { Label(category, systemImage: "folder").font(.caption) }
                    if let items = event.subtasks, !items.isEmpty {
                        DisclosureGroup("サブタスク \(items.filter(\.isDone).count)/\(items.count)") {
                            ForEach(items) { Label($0.title, systemImage: $0.isDone ? "checkmark.circle.fill" : "circle") }
                        }.font(.caption)
                    }
                    Text(event.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
            }
        }
        .flowScreen()
        .searchable(text: $query, prompt: "履歴を検索")
        .navigationTitle("履歴")
    }

    private func label(_ outcome: Outcome) -> String {
        switch outcome {
        case .completed: return "達成"
        case .failed: return "失敗"
        case .carried: return "繰り越し"
        case .deleted: return "削除"
        }
    }

    private func icon(_ outcome: Outcome) -> String {
        switch outcome {
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .carried: return "arrow.right.circle"
        case .deleted: return "trash"
        }
    }
}
