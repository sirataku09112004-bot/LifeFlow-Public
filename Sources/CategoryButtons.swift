import SwiftUI

struct FlowCategoryManager: View {
    @EnvironmentObject var store: FlowStore
    @Environment(\.dismiss) var dismiss
    @State private var names: [String]
    @State private var draft: String
    @State private var saveFailure: String?
    init(names: [String], suggestedName: String? = nil) {
        _names = State(initialValue: names)
        let suggested = FlowCategories.normalized(suggestedName) ?? ""
        _draft = State(initialValue: names.contains(suggested) ? "" : suggested)
    }
    var cleanDraft: String { FlowCategories.normalized(draft) ?? "" }
    var canAdd: Bool { !cleanDraft.isEmpty && cleanDraft.count <= 40 && !names.contains(cleanDraft) && names.count < 30 }
    var body: some View {
        NavigationStack {
            Form {
                Section("新しいボタン") {
                    HStack {
                        TextField("例：仕事・生活・趣味", text: $draft).onSubmit { add() }
                        Button("追加") { add() }.disabled(!canAdd)
                    }.buttonStyle(.borderless)
                    if !cleanDraft.isEmpty && names.contains(cleanDraft) { Text("同じ名前のボタンは登録済みです").font(.caption).foregroundStyle(.secondary) }
                    if cleanDraft.count > 40 { Text("40文字以内で入力してください").font(.caption).foregroundStyle(.red) }
                }
                Section {
                    ForEach(names, id: \.self) { Text($0) }
                        .onDelete { names.remove(atOffsets: $0) }
                        .onMove { names.move(fromOffsets: $0, toOffset: $1) }
                    if names.isEmpty { Text("まだ登録されていません").foregroundStyle(.secondary) }
                } header: { Text("登録済み（\(names.count)/30）") } footer: { Text("右のハンドルで並べ替え、−で削除できます。ここでの削除はボタンだけに反映し、ToDoや履歴のカテゴリは変更しません。") }
                if let message = saveFailure { Text(message).foregroundStyle(.red) }
            }
            .environment(\.editMode, .constant(.active))
            .flowScreen()
            .navigationTitle("カテゴリボタン")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if canAdd { names.append(cleanDraft); draft = "" }
                    if store.saveCategoryButtons(names) { dismiss() } else { saveFailure = store.error ?? "保存できませんでした" }
                }.disabled(!store.ready || (!cleanDraft.isEmpty && !canAdd)) }
            }
        }
    }
    func add() { guard canAdd else { return }; names.append(cleanDraft); draft = "" }
}
