import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct LifeFlowProbeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LifeFlowProbeControl") {
            ControlWidgetButton(action: FlowProbeStandardIntent()) {
                Label("LifeFlow 診断A", systemImage: "checkmark.circle")
            }
        }
        .displayName("LifeFlow 診断A")
        .description("ホーム画面と同じAを呼び出します。")
    }
}

@available(iOS 17.0, *)
struct LifeFlowProbeConfigurationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LifeFlowWidgetConfigurationProbe",
                               intent: FlowProbeConfigurationIntent.self,
                               provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                Text("設定読み込み診断")
                    .font(.caption.weight(.bold))
                    .unredacted()
                if entry.isPlaceholder {
                    Text("設定を読み込み中")
                        .font(.caption2)
                        .unredacted()
                } else {
                    Text(entry.choice ?? "編集で選択")
                        .font(.caption2)
                        .lineLimit(1)
                    Button(intent: FlowProbeStandardIntent()) {
                        Label("A 標準", systemImage: "circle")
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("probe-configured-standard")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color(.systemGroupedBackground) }
        }
        .configurationDisplayName("設定読み込み診断")
        .description("編集画面で診断用の選択肢を読み込みます。")
        .supportedFamilies([.systemSmall])
    }

    struct Entry: TimelineEntry {
        let date = Date()
        let choice: String?
        var isPlaceholder = false
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(choice: nil, isPlaceholder: true) }

        func snapshot(for configuration: FlowProbeConfigurationIntent, in context: Context) async -> Entry {
            Entry(choice: configuration.choice?.label)
        }

        func timeline(for configuration: FlowProbeConfigurationIntent, in context: Context) async -> Timeline<Entry> {
            FlowWidgetProbeLog.record(.configurationTimeline)
            return Timeline(entries: [Entry(choice: configuration.choice?.label)], policy: .never)
        }
    }
}
