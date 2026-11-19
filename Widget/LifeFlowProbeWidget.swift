import AppIntents
import SwiftUI
import WidgetKit

@main
struct LifeFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeFlowTodayWidget()
        if #available(iOS 17.0, *) {
            LifeFlowProbeWidget()
        }
    }
}

@available(iOS 17.0, *)
struct LifeFlowProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FlowWidgetProbe.kind, provider: Provider()) { entry in
            LifeFlowProbeView(entry: entry)
        }
        .configurationDisplayName("ウィジェット動作診断")
        .description("ボタンの届き方を比べます。ToDoは操作しません。")
        .supportedFamilies([.systemMedium])
    }

    struct Entry: TimelineEntry {
        let date = Date()
        let received: Set<FlowWidgetProbe>
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(received: []) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(entry())
        }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [entry()], policy: .never))
        }
        private func entry() -> Entry {
            Entry(received: Set(FlowWidgetProbe.allCases.filter { FlowWidgetProbeLog.sharedReceipt($0) != nil }))
        }
    }
}

@available(iOS 17.0, *)
private struct LifeFlowProbeView: View {
    let entry: LifeFlowProbeWidget.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ウィジェット動作診断")
                .font(.caption.weight(.bold))
            Grid(horizontalSpacing: 6, verticalSpacing: 4) {
                GridRow {
                    button(.standard, intent: FlowProbeStandardIntent())
                    button(.widget, intent: FlowProbeWidgetIntent())
                }
                GridRow {
                    button(.app, intent: FlowProbeAppIntent())
                    button(.legacy, intent: FlowProbeLegacyIntent())
                }
                GridRow {
                    button(.foreground, intent: FlowProbeForegroundIntent())
                    Toggle(isOn: entry.received.contains(.toggle),
                           intent: FlowProbeToggleIntent(value: FlowProbeToggleIntent.expected)) {
                        Text(FlowWidgetProbe.toggle.label).font(.caption2.weight(.semibold))
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("probe-toggle")
                }
                GridRow {
                    Link(destination: FlowWidgetProbe.linkURL) { label(.link) }
                        .accessibilityIdentifier("probe-link")
                    button(.progress, intent: FlowProbeProgressIntent())
                }
            }
        }
        .containerBackground(for: .widget) { Color(.systemGroupedBackground) }
    }

    private func button(_ probe: FlowWidgetProbe, intent: some AppIntent) -> some View {
        Button(intent: intent) { label(probe) }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.received.contains(probe) ? "\(probe.label) 受信済み" : probe.label)
            .accessibilityIdentifier("probe-\(probe.rawValue)")
    }

    private func label(_ probe: FlowWidgetProbe) -> some View {
        let received = entry.received.contains(probe)
        return Label(probe.label, systemImage: received ? "checkmark.circle.fill" : "circle")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .accessibilityValue(received ? "受信済み" : "未記録")
    }
}
