import SwiftUI

struct FlowChecklistEditor: View {
    @Binding var items: [FlowSubtask]
    var goalMode = false
    @State private var draft = ""
    var body: some View {
        Section {
            ForEach($items) { $item in
                HStack {
                    Button { item.isDone.toggle() } label: { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isDone ? Color.green : Color.secondary) }
                        .accessibilityLabel(item.isDone ? "未完了に戻す" : "サブタスクを完了")
                    TextField("サブタスク", text: $item.title, axis: .vertical)
                    Button(role: .destructive) { let id = item.id; items.removeAll { $0.id == id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("サブタスクを削除")
                }.buttonStyle(.borderless)
            }
            HStack {
                TextField("小さな作業を追加", text: $draft).onSubmit { add() }
                Button(action: add) { Image(systemName: "plus.circle.fill") }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 200 || items.count >= 50).accessibilityLabel("サブタスクを追加")
            }
        } header: {
            Text("サブタスク（\(items.filter(\.isDone).count)/\(items.count)完了）")
        } footer: {
            Text(goalMode ? "＋で追加してから目標を保存してください。最大50件。" : "＋で追加してからToDoを保存してください。最大50件。")
        }
    }
    func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200, items.count < 50 else { return }
        items.append(FlowSubtask(title: title)); draft = ""
    }
}
