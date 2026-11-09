import SwiftUI

enum FlowTheme {
    static let background = Color(red: 245 / 255, green: 250 / 255, blue: 254 / 255)
    static let card = Color.white
    static let pale = Color(red: 224 / 255, green: 242 / 255, blue: 254 / 255)
    static let accent = Color(red: 57 / 255, green: 169 / 255, blue: 232 / 255)
    static let ink = Color(red: 35 / 255, green: 74 / 255, blue: 99 / 255)
    static let action = Color(red: 22 / 255, green: 94 / 255, blue: 136 / 255)
    static let star = Color(red: 155 / 255, green: 109 / 255, blue: 0)
}

extension View {
    func flowScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(FlowTheme.background)
            .foregroundStyle(FlowTheme.ink)
    }
}

struct FlowHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("ToDo") {
                    Text("＋からタスクを追加。日付を文章に書くと、予定日に反映します。例「明日買い物」「11月15日レポート提出」。")
                    Text("✓で達成、×で失敗を記録します。通常のToDoは×で翌営業日（月〜金、祝日は未判定）へ移ります。日は午前4時に切り替わります。")
                    Text("タスク名をタップすると編集できます。★でお気に入り、歯車で通知・履歴・バックアップを開けます。")
                }
                Section("年間目標・習慣") {
                    Text("年間目標のサブタスクは今日のToDoへ追加できます。目標のチェックは年間目標から操作します。")
                    Text("習慣はToDoで✓・×を記録します。習慣の詳細で日別の記録や週の目標を確認でき、休養日も記録できます。")
                }
            }
            .flowScreen()
            .navigationTitle("使い方")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
