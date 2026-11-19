import SwiftUI

struct FlowWidgetProbeResultsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(FlowWidgetContainer.file == nil ? "共有データ領域 利用不可" : "共有データ領域 利用可")
                    Text("時刻が出た操作はLifeFlowのコードまで届いています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(FlowWidgetProbe.allCases, id: \.self) { probe in
                    let receipt = FlowWidgetProbeLog.appReceipt(probe)
                    LabeledContent(probe.label, value: resultText(receipt))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(probe.label)
                        .accessibilityValue(resultText(receipt))
                        .accessibilityIdentifier("probe-result-\(probe.rawValue)")
                }
            }
            .navigationTitle("ウィジェット診断結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: FlowWidgetProbe.allCases.map { probe in
                        "\(probe.label) \(resultText(FlowWidgetProbeLog.appReceipt(probe)))"
                    }.joined(separator: "\n"))
                }
            }
        }
    }

    private func resultText(_ receipt: FlowWidgetProbeReceipt?) -> String {
        guard let receipt else { return "未記録" }
        let time = receipt.date.formatted(date: .omitted, time: .standard)
        let storage = receipt.shared ? "" : "・本体内のみ"
        let payload = receipt.payloadOK ? "" : "・引数不一致"
        return "\(time) \(receipt.process)\(storage)\(payload)"
    }
}
