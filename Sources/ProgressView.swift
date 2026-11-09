import SwiftUI

struct FlowProgressView: View {
    @EnvironmentObject var store: FlowStore
    @Environment(\.dismiss) var dismiss
    @State private var count = 7
    var days: [FlowDaySummary] { FlowInsights.days(history: store.data.history, count: count, now: Date(), clock: store.clock) }
    var completed: Int { days.reduce(0) { $0 + $1.completed } }
    var failed: Int { days.reduce(0) { $0 + $1.failed } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("期間", selection: $count) { Text("7日間").tag(7); Text("30日間").tag(30) }.pickerStyle(.segmented)
                    HStack {
                        Label("達成 \(completed)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Label("失敗 \(failed)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                    if completed + failed > 0 {
                        Text("達成率 \(Int((Double(completed) / Double(completed + failed) * 100).rounded()))%")
                    } else { Text("この期間の達成・失敗はまだありません") }
                    Text("操作した日を午前4時区切りで集計します。達成率＝達成÷（達成＋失敗）。自動繰越・削除は含みません。同じToDoへの複数回の操作もそれぞれ数えます。").font(.caption).foregroundStyle(.secondary)
                }
                Section("現在の予定") {
                    LabeledContent("今日までの未完了", value: "\(store.data.tasks.filter { $0.day <= store.clock.today() }.count)件")
                    LabeledContent("予定すべて", value: "\(store.data.tasks.count)件")
                    LabeledContent("お気に入り", value: "\(store.data.tasks.filter { $0.favorite }.count)件")
                }
                NavigationLink("履歴を確認") { FlowHistory() }
                Section("日別") {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(store.clock.label(day.day)).font(.subheadline)
                                Spacer()
                                Text("✓ \(day.completed)  × \(day.failed)").font(.caption).monospacedDigit()
                            }
                            if let rate = day.rate { ProgressView(value: rate).tint(.green) }
                            else { Text("記録なし").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                }
            }
            .flowScreen()
            .navigationTitle("振り返り")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

